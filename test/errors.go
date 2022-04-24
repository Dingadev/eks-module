package test

// NetworkInterfacesStillExist is an error returned by waitForNetworkInterfacesToBeDeletedE when the network interfaces
// that are waiting to be deleted have not been deleted yet.
type NetworkInterfacesStillExist struct{}

func (err NetworkInterfacesStillExist) Error() string {
	return "Network interfaces still exist"
}
