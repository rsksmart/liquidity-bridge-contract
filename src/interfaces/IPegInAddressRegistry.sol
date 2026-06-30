// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Peg-In Address Registry interface
/// @notice Maintains registered Flyover peg-in Rootstock addresses and returns the
/// corresponding Bitcoin derivation addresses for the current powpeg composition.
interface IPegInAddressRegistry {
	/// @notice Bitcoin address encoding formats supported for derivation addresses
	enum Encoding { BASE58, BECH32, BECH32M }

	/// @notice Emitted when a Rootstock address is registered for peg-in discovery
	/// @param addr The registered Rootstock destination address
	/// @param registrant The account that submitted the registration
	/// @param registrationRoot The updated running hash after this registration
	event AddressRegistered(
		address indexed addr,
		address indexed registrant,
		bytes32 indexed registrationRoot
	);

	/// @notice Registers a Rootstock address for peg-in discovery
	/// @param addr The Rootstock destination address to register
	function registerAddress(address addr) external;

	/// @notice Returns the Bitcoin derivation address for a Rootstock address
	/// @dev The derivation address is deterministic from the Rootstock address and the
	/// current powpeg composition. Clients call this before sending BTC; LPs use it to
	/// know which deposit addresses to monitor on the Bitcoin network
	/// @param addr The Rootstock destination address
	/// @return derivationAddress The encoded Bitcoin deposit address
	/// @return encoding The encoding format of the derivation address
	function getPegInAddress(address addr) external view returns (bytes memory derivationAddress, Encoding encoding);

	/// @notice Returns Bitcoin derivation addresses for multiple Rootstock addresses
	/// @dev Is the array version of `getPegInAddress`
	/// @param addrs The Rootstock destination addresses to derive
	/// @return derivationAddresses The encoded Bitcoin deposit addresses
	/// @return encoding The encoding format shared by all derivation addresses
	function getPegInAddresses(address[] calldata addrs)
		external
		view
		returns (bytes[] memory derivationAddresses, Encoding encoding);

	/// @notice Returns the on-chain running hash of all registrations
	/// @dev Off-chain LPs compare this value against a hash computed locally from
	/// `AddressRegistered` events to verify they hold the complete registration set
	/// @return The current `registrationRoot` accumulator
	function getRegistrationRoot() external view returns (bytes32);

	/// @notice Returns whether a Rootstock address is registered
	/// @dev Used by on-chain peg-in logic to require registration before processing
	/// @param addr The Rootstock destination address to check
	/// @return True if the address is registered
	function isRegistered(address addr) external view returns (bool);

	/// @notice Returns the block number at which a Rootstock address was registered
	/// @param addr The Rootstock destination address
	/// @return The block number of the registration transaction
	function getRegistrationBlock(address addr) external view returns (uint256);

	/// @notice Returns the account that registered a Rootstock address
	/// @param addr The Rootstock destination address
	/// @return The registrant address, or `address(0)` if not registered
	function getRegistrant(address addr) external view returns (address);

	/// @notice Returns the total number of registered Rootstock addresses
	/// @return The count of addresses in the registry
	function getRegistrationCount() external view returns (uint256);
}
