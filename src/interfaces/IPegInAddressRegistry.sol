// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title IPegInAddressRegistry
/// @notice Frozen interface (E0 design-lock) for the permissionless, deposit-gated
/// peg-in address registry. A static BTC deposit address is derived from an RSK address
/// against the current powpeg; registration is gated by an SPV proof of a BTC deposit to
/// that derived address, with no ECDSA signature required.
/// @author Rootstock Labs
interface IPegInAddressRegistry {
    enum Encoding { BASE58, BECH32, BECH32M }

    /// @notice Emitted when an RSK address is registered
    /// @param addr The RSK address that was registered
    /// @param registrationRoot The running-hash root after this registration
    event AddressRegistered(address indexed addr, bytes32 indexed registrationRoot);

    /// @notice Register an RSK address, gated by an SPV proof of a BTC deposit to the
    /// address derived for `addr`. Permissionless: any caller may register on behalf of `addr`.
    /// @param addr The RSK address to register
    /// @param btcTx The raw BTC transaction (without witness data)
    /// @param blockHeight The BTC block height of the transaction
    /// @param merkleProof The partial merkle tree proving inclusion of the transaction
    function registerAddress(
        address addr,
        bytes calldata btcTx,
        uint256 blockHeight,
        bytes calldata merkleProof
    ) external;

    /// @notice Returns the BTC deposit address derived for `addr` against the current powpeg
    /// @param addr The RSK address
    /// @return The encoded BTC deposit address and its encoding
    function getPegInAddress(address addr) external view returns (bytes memory, Encoding);

    /// @notice Returns the BTC deposit addresses derived for a batch of RSK addresses
    /// @param addrs The RSK addresses
    /// @return derivationAddresses The encoded BTC deposit address for each input, in order
    /// @return encoding The shared encoding of the returned addresses
    function getPegInAddresses(address[] calldata addrs)
        external view returns (bytes[] memory derivationAddresses, Encoding encoding);

    /// @notice Returns the current registration running-hash root
    function getRegistrationRoot() external view returns (bytes32);

    /// @notice Returns whether `addr` has been registered
    function isRegistered(address addr) external view returns (bool);

    /// @notice Returns the block number at which `addr` was registered (0 if not registered)
    function getRegistrationBlock(address addr) external view returns (uint256);

    /// @notice Returns the number of registered addresses
    function getRegistrationCount() external view returns (uint256);
}
