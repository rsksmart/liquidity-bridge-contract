// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Commit-first peg-in interface
/// @notice The claim and settlement surface of the commit-first peg-in redesign: the user's
/// BTC deposit is the only commitment, and liquidity providers compete to serve it by
/// fronting RBTC (requestPegIn) and later settling against the bridge (resolvePegIn).
/// PegInContract implements this surface next to the untouched quote flow.
/// @dev ABI-stable surface shared by PegInContract and off-chain consumers.
interface IPegInCommitFirst {

    /// @notice Emitted when a peg-in is claimed and the user is paid, in the same
    /// transaction
    /// @dev callSuccess is reserved for contract-call delivery; plain transfers always emit true.
    /// @param pegInId The id under which the claim was recorded
    /// @param claimer The account that fronted the RBTC and holds the claim
    /// @param rskAddr The RSK destination address that received the funds
    /// @param amount The gross peg-in amount, in wei — the deposit output's satoshi value
    /// scaled by 10**10, never a caller-supplied figure
    /// @param netToUser The amount delivered to the user (amount minus fee), in wei
    /// @param callSuccess Whether the delivery call succeeded
    event PegInRequested(
        bytes32 indexed pegInId,
        address indexed claimer,
        address indexed rskAddr,
        uint256 amount,
        uint256 netToUser,
        bool callSuccess
    );

    /// @notice Emitted when resolvePegIn credits balances after a positive bridge return
    /// @param pegInId The settled peg-in id
    /// @param claimer The claimer from the claim record
    /// @param registrant The account credited the registrant fee; address(0) if none
    /// @param released The amount the bridge released to this contract, in wei
    /// @param claimerPayout frontedAmount + feeAtClaim - registrantFee, in wei
    /// @param registrantFee Amount credited to registrant this call, in wei; 0 if none
    /// @param userPayout 0
    event PegInResolved(
        bytes32 indexed pegInId,
        address indexed claimer,
        address indexed registrant,
        uint256 released,
        uint256 claimerPayout,
        uint256 registrantFee,
        uint256 userPayout
    );

    /// @notice Reverts requestPegIn when the peg-in already has a claimer
    /// @dev First check in requestPegIn to limit gas for claim races. The deposit txid is
    /// hashed out of the raw transaction before it, because the id is keyed on that txid.
    /// @param pegInId The id of the already-claimed peg-in
    error PegInAlreadyProcessed(bytes32 pegInId);

    /// @notice Reverts resolvePegIn when no claim record exists for the peg-in
    /// @param pegInId The id of the unclaimed peg-in
    error PegInNotClaimed(bytes32 pegInId);

    /// @notice Reverts requestPegIn when the destination address has no registration record
    /// @param rskAddr The unregistered RSK destination address
    error AddressNotRegistered(address rskAddr);

    /// @notice Reverts requestPegIn when the presented transaction has no output paying the
    /// deposit address derived from the destination address
    /// @dev The check that makes the peg-in amount a value read off the deposit instead of one
    /// declared by the caller.
    /// Without it any confirmed txid pairs with any registered destination, so a dust claim
    /// locks the real depositor out under PegInAlreadyProcessed. Same rule the registry
    /// enforces at registration, through the same shared helper.
    /// @param rskAddr The destination address whose derived deposit output was not found
    /// @param btcTxHash The hash of the presented transaction
    error DepositOutputNotFound(address rskAddr, bytes32 btcTxHash);

    /// @notice Reverts requestPegIn when the deposit lacks the confirmations the
    /// configuration requires for its amount
    /// @dev The amount driving the tier lookup is the one read off the deposit output, so
    /// understating a large deposit to buy the low tier is not expressible.
    /// @param have The confirmations the bridge reports
    /// @param required The confirmations the active configuration requires
    error InsufficientConfirmations(uint256 have, uint256 required);

    /// @notice Reverts requestPegIn when msg.value does not equal the amount minus the fee
    /// @dev The credential is capital: there is no LP-only gate and no signature.
    /// @param expected The required msg.value (amount minus fee), in wei
    /// @param actual The msg.value sent, in wei
    error IncorrectFronting(uint256 expected, uint256 actual);

    /// @notice Claims a confirmed BTC deposit by fronting the net amount in RBTC, which is
    /// delivered to the destination address in the same transaction
    /// @dev Takes the raw deposit transaction, not an amount and not a txid. The gross amount
    /// is READ from the output paying the address derived for rskAddr, and the txid is hashed
    /// from the same bytes, so the SPV proof, the peg-in id and the amount provably describe
    /// one transaction. Nothing about the deposit's value is caller-supplied.
    ///
    /// Payable: msg.value must equal the amount read from the deposit minus the fee. Stores
    /// claimer, fronted amount, and feeAtClaim because the configuration can change before
    /// settlement. opReturn is accepted but not used for plain transfers.
    /// @param rskAddr The RSK destination address of the peg-in
    /// @param btcTxSerialized The witness-stripped raw BTC deposit transaction
    /// @param opReturn The OP_RETURN payload of the deposit, if any
    /// @param btcBlockHash The hash of the Bitcoin block containing the deposit
    /// @param merkleBranchPath The path bitmap of the merkle branch proving inclusion
    /// @param merkleBranchHashes The hashes of the merkle branch proving inclusion
    /// @return pegInId The id under which the claim was recorded:
    /// keccak256(rskAddr ++ btcTxHash), with btcTxHash hashed from btcTxSerialized — the same
    /// id resolvePegIn re-derives at settlement
    function requestPegIn(
        address rskAddr,
        bytes calldata btcTxSerialized,
        bytes calldata opReturn,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external payable returns (bytes32 pegInId);

    /// @notice Settles a peg-in against the bridge once the deposit reaches the bridge's
    /// required depth, and distributes the released funds from the records written at
    /// request and registration time
    /// @dev Reads registrant from registry storage, not from calldata. The bridge pays this
    /// contract (shouldTransferToContract = true); funds are split from on-chain records.
    /// @param rskAddr The RSK destination address of the peg-in
    /// @param btcRawTransaction The raw witness-stripped deposit transaction
    /// @param partialMerkleTree The partial merkle tree proving the deposit's inclusion
    /// @param height The Bitcoin block height of the deposit
    /// @return registerResult The bridge's status: the released amount, or its negative
    /// error code, same convention as registerPegIn
    function resolvePegIn(
        address rskAddr,
        bytes calldata btcRawTransaction,
        bytes calldata partialMerkleTree,
        uint256 height
    ) external returns (int256 registerResult);
}
