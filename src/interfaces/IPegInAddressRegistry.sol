// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title PegInAddressRegistry interface
/// @notice Discovery surface for commit-first peg-ins. Derives the deterministic BTC deposit
/// address for an RSK destination address and records deposit-gated registrations, so
/// liquidity providers can discover confirmed deposits on-chain.
/// @dev Walkthrough (WALKTHROUGH-pegin.md) anchors: steps 3-4 (reads), step 8 (registration),
/// step 9 (root verification); decisions D3-D8. This interface is frozen (S0): any change to
/// it is a cross-lane ABI event, not a side effect of another task.
interface IPegInAddressRegistry {

    /// @notice The encoding of an address payload returned by the registry
    /// @dev Enum values are ABI, so all three freeze here. Only BASE58 is produced this
    /// sprint; BECH32 and BECH32M are reserved so consumers can branch on them without a
    /// future ABI break. Walkthrough anchor: step 3.
    enum Encoding { BASE58, BECH32, BECH32M }

    /// @notice The registration record of an RSK destination address, packed in one storage
    /// slot. An address counts as registered while registrationBlock != 0.
    /// @dev Walkthrough anchor: step 4, decision D5 (packed layout, registrant carried from
    /// day 1). The registrant is paid the registration fee at settlement (step 14, sprint 2).
    /// @param registrant The account that sent registerAddress (watchtower, RIF Relay, or any
    /// sponsor); always recorded from msg.sender
    /// @param registrationBlock The RSK block of the registration; anchors the slash deadline
    /// (exception A5, sprint 2)
    struct Registration {
        address registrant;
        uint96 registrationBlock;
    }

    /// @notice Emitted when an address is registered. This event is the flyover deposit index
    /// that Bitcoin lacks: liquidity providers watch it to discover serveable deposits.
    /// @dev The event is also the durable registrant record: the storage slot's registrant is
    /// zeroed after the step 14 payout (D5's already-paid marker), so payout audits and
    /// watchtower reconciliation filter this event by registrant. registrationRoot is not
    /// indexed: no consumer filters by root value, the LPS reads it from the event body to
    /// compare against its local fold. Walkthrough anchors: step 8 (emission), step 9
    /// (LPS watch), decisions D5, D7.
    /// @param rskAddr The registered RSK destination address
    /// @param registrant The account that sent registerAddress (msg.sender); paid the
    /// registrant fee at settlement (step 14, sprint 2)
    /// @param registrationRoot The accumulator root after folding this address in
    event AddressRegistered(
        address indexed rskAddr,
        address indexed registrant,
        bytes32 registrationRoot
    );

    /// @notice Reverts registerAddress when the address already has a registration record
    /// @dev Cheapest check first, so the loser of a registration race burns minimal gas.
    /// Walkthrough anchor: step 8, check 0.
    /// @param rskAddr The address that is already registered
    error AddressAlreadyRegistered(address rskAddr);

    /// @notice Reverts registerAddress when the presented BTC transaction has no output
    /// paying the deposit address derived from the RSK address
    /// @dev The registry never trusts a presented address: it re-derives and matches outputs.
    /// Walkthrough anchor: step 8, check 2.
    /// @param rskAddr The address whose derived deposit output was not found
    error DepositOutputNotFound(address rskAddr);

    /// @notice Reverts registerAddress when the bridge does not report the deposit
    /// transaction as confirmed
    /// @dev The confirmation lookup is read-only; registering never consumes the peg-in.
    /// Walkthrough anchors: step 8, check 3; decision D8.
    /// @param btcTxHash The hash of the unconfirmed deposit transaction
    error DepositNotConfirmed(bytes32 btcTxHash);

    /// @notice Reverts registerAddress when the deposit output paying the derived address is
    /// below the minimum registrable amount
    /// @dev The economic spam gate: without a floor, a 546-sat dust output satisfies the
    /// deposit check and bloats every LPS watch list at dust prices. The floor makes
    /// "registration costs real BTC" literal. Walkthrough anchor: step 8.
    /// @param value The deposit output value found, in satoshis
    /// @param minimum The minimum registrable deposit, in satoshis
    error DepositBelowMinimum(uint256 value, uint256 minimum);

    /// @notice Raised when an address derivation is attempted before the PegInContract is wired
    error PegInContractNotSet();

    /// @notice Raised when a batch request exceeds the registry batch cap
    /// @param requested The number of addresses requested
    /// @param max The maximum allowed batch size
    error BatchTooLarge(uint256 requested, uint256 max);

    /// @notice Derives the deterministic BTC deposit address for an RSK destination address
    /// @dev The address is a prediction of what the bridge recomputes at settlement, byte for
    /// byte: it depends only on the RSK address, fixed protocol constants, and the active
    /// powpeg script, so it is stable per user and tied to no liquidity provider.
    /// Walkthrough anchors: step 3, decision block 3·D, decisions D3-D4.
    /// @param rskAddr The RSK destination address of the peg-in
    /// @return payload The raw base58check payload of the deposit address; the caller
    /// (SDK/LPS) encodes it to the address string
    /// @return encoding The encoding tag of the payload (BASE58 this sprint)
    function getPegInAddress(address rskAddr) external view returns (bytes memory payload, Encoding encoding);

    /// @notice Batch variant of getPegInAddress
    /// @dev Walkthrough anchor: step 3.
    /// @param rskAddrs The RSK destination addresses to derive for
    /// @return payloads The raw address payloads, one per input address, in input order
    /// @return encoding The encoding tag shared by every payload in the batch
    function getPegInAddresses(address[] calldata rskAddrs)
        external
        view
        returns (bytes[] memory payloads, Encoding encoding);

    /// @notice Tells whether an RSK destination address has a registration record
    /// @dev True while the packed record's registrationBlock != 0. Walkthrough anchors:
    /// step 4, decision D5.
    /// @param rskAddr The RSK destination address to look up
    /// @return registered Whether the address is registered
    function isRegistered(address rskAddr) external view returns (bool registered);

    /// @notice Returns the full registration record of an RSK destination address
    /// @dev One read serves both settlement (registrant fee, step 14) and the slash deadline
    /// anchor (exception A5). Walkthrough anchors: step 4, decision D5.
    /// @param rskAddr The RSK destination address to look up
    /// @return registration The packed {registrant, registrationBlock} record; zeroed when
    /// the address is not registered
    function getRegistration(address rskAddr) external view returns (Registration memory registration);

    /// @notice Returns the running registration accumulator root
    /// @dev One 32-byte slot folding every registration in order:
    /// registrationRoot = keccak256(prevRoot ++ rskAddr). An LPS recomputes the same fold
    /// locally to prove its replayed watch list is complete after a restart. Walkthrough
    /// anchors: step 9, decision D6.
    /// @return registrationRoot The current accumulator root
    function getRegistrationRoot() external view returns (bytes32 registrationRoot);

    /// @notice Registers an RSK destination address by proving a confirmed BTC deposit pays
    /// its derived deposit address
    /// @dev Permissionless and deposit-gated: anyone may call, but only with an SPV proof of
    /// a real confirmed deposit, so registry spam costs real BTC. Returns nothing; its
    /// effects are the packed record (registrant = msg.sender), the AddressRegistered event,
    /// and the root fold, written atomically. Walkthrough anchors: step 8, decisions D5, D8.
    /// @param rskAddr The RSK destination address to register
    /// @param btcTxSerialized The witness-stripped serialization of the deposit transaction
    /// @param btcBlockHash The hash of the Bitcoin block containing the deposit
    /// @param merkleBranchPath The path bitmap of the merkle branch proving inclusion
    /// @param merkleBranchHashes The hashes of the merkle branch proving inclusion
    function registerAddress(
        address rskAddr,
        bytes calldata btcTxSerialized,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external;
}
