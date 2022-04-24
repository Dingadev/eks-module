# -*- coding: utf-8 -*-
from __future__ import print_function
import ddt
import unittest
import moto
import moto.instance_metadata.urls
from moto.core.responses import BaseResponse
from six.moves.urllib.parse import urlparse

import map_ec2_tags_to_node_labels


@ddt.ddt
class MapEC2TagsToNodeLabelsTestCase(unittest.TestCase):
    """
    Test cases for modules/eks-scripts/bin/map-ec2-tags-to-node-labels
    """
    REGION = 'us-west-2'
    AVAILABILITY_ZONE = 'us-west-2c'

    def setUp(self):
        # Swap out the instance metadata responder in moto with DynamicInstanceMetadataResponder.
        self.instance_metadata_responder = DynamicInstanceMetadataResponder(self.AVAILABILITY_ZONE)
        for path in moto.instance_metadata.urls.url_paths:
            moto.instance_metadata.urls.url_paths[path] = self.instance_metadata_responder.metadata_response

        # `mock_ec2` (non-deprecated) only works with boto3. Since we use botocore directly instead of boto3, we need to
        # rely on the deprecated version.
        self.mock_ec2 = moto.mock_ec2_deprecated()
        self.mock_ec2.start()

    def tearDown(self):
        self.mock_ec2.stop()

    def get_ec2_client(self):
        """
        Return a new EC2 client. We use a new client for every call in this test because there is a weird issue in the
        combination of moto, botocore, and python 3 where multiple calls using the same client object fails.
        """
        return map_ec2_tags_to_node_labels.get_ec2_client(self.REGION)

    def setup_ec2_instance_with_tags(self, tags):
        """ Register a fake EC2 instance with tags to moto """
        resp = self.get_ec2_client().run_instances(ImageId='ami-00000000000', MinCount=1, MaxCount=1)
        instance = resp['Instances'][0]
        instance_id = instance['InstanceId']
        self.get_ec2_client().create_tags(
            Resources=[instance_id],
            Tags=[{
                'Key': key,
                'Value': tags[key]
            } for key in tags],
        )
        return instance_id

    def test_get_instance_id_queries_metadata_endpoint(self):
        faux_instance_id = 'i-03ad6ffffbe49e2dd'
        self.instance_metadata_responder.update_instance_id(faux_instance_id)
        self.assertEqual(map_ec2_tags_to_node_labels.get_instance_id(), faux_instance_id)

    def test_get_region_queries_metdata_endpoint_and_drops_zone_id(self):
        self.assertEqual(map_ec2_tags_to_node_labels.get_region(), self.REGION)

    def test_get_ec2_instance_tags_gets_tags_for_instance_by_metadata(self):
        seed_tags = {
            'Name': 'I am a teapot',
            'company': 'Gruntwork',
        }
        instance_id = self.setup_ec2_instance_with_tags(seed_tags)
        self.instance_metadata_responder.update_instance_id(instance_id)
        tags = map_ec2_tags_to_node_labels.get_ec2_instance_tags('')
        self.assertEqual(tags, seed_tags)

    def test_get_ec2_instance_tags_filters_tags_by_prefix(self):
        seed_tags = {
            'Name': 'I am a teapot',
            'company': 'Gruntwork',
            'label/code': '418',
            'label/other_code': '451',
        }
        expected_tags = {
            'label/code': '418',
            'label/other_code': '451',
        }
        instance_id = self.setup_ec2_instance_with_tags(seed_tags)
        self.instance_metadata_responder.update_instance_id(instance_id)
        tags = map_ec2_tags_to_node_labels.get_ec2_instance_tags('label')
        self.assertEqual(tags, expected_tags)

    @ddt.data(
        {
            'test': 'I am a teapot',
            'expected': 'I-am-a-teapot',
        },
        {
            'test': '1.21-GigaWatts',
            'expected': '1.21-GigaWatts',
        },
        {
            'test': '--LeadingANDTrailingDashes--',
            'expected': 'LeadingANDTrailingDashes',
        },
        {
            'test': '@LeadingANDTrailing@',
            'expected': 'LeadingANDTrailing',
        },
        {
            'test': u'unicode:テストthis',
            'expected': 'unicode----this',
        },
    )
    def test_format_string_for_node_label(self, query):
        self.assertEqual(map_ec2_tags_to_node_labels.format_string_for_node_label(query['test']), query['expected'])

    def test_format_tags_for_node_label(self):
        tags = {
            'Name': 'time machine',
            'energy': '1.21-GigaWatts',
            '-@base@-': 'delorean',
        }
        node_labels = map_ec2_tags_to_node_labels.format_tags_as_node_labels(tags)
        self.assertEqual(
            node_labels,
            'ec2.amazonaws.com/base=delorean,ec2.amazonaws.com/Name=time-machine,ec2.amazonaws.com/energy=1.21-GigaWatts',
        )


class DynamicInstanceMetadataResponder(BaseResponse):
    """
    Extends moto.instance_metadata.InstanceMetadataResponse to be able to dynamically adjust the responses for certain
    metadata queries. Specifically:

    - instance id
    - availability zone
    """

    def __init__(self, availability_zone):
        super(DynamicInstanceMetadataResponder, self).__init__()
        self.instance_id = None
        self.availability_zone = availability_zone

        # Keep track of the original instance metadata responder so we can use it for the other supported metadata url
        # paths
        self.original_instance_metadata_responder = moto.instance_metadata.urls.instance_metadata

    def update_instance_id(self, instance_id):
        self.instance_id = instance_id

    def metadata_response(self, request, full_url, headers):
        parsed_url = urlparse(full_url)
        path = parsed_url.path

        # Strip prefix if it is there
        meta_data_prefix = '/latest/meta-data/'
        if path.startswith(meta_data_prefix):
            path = path[len(meta_data_prefix):]

        if path == 'instance-id':
            result = self.instance_id
        elif path == 'placement/availability-zone':
            result = self.availability_zone
        elif path == '/latest/api/token':
            result = ''
        else:
            return self.original_instance_metadata_responder.metadata_response(request, full_url, headers)

        return 200, headers, result
