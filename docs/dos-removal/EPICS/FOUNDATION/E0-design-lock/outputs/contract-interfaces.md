# Frozen contract interfaces (PoC)

Output of S0.2. Frozen for the PoC; later iterations may change them. Source: proposal "Suggested contracts", adjusted for the locked E0 decisions. Scoped to what the PoC needs.

## IFlyoverConfigurations

Holds both peg-in and peg-out configuration. `callTime` and `expireTime` are kept separate per the S0.2 decision. Setters are time-locked (E1.5).

```solidity
interface IFlyoverConfigurations {
    struct ConfirmationTier {
        uint256 maxAmount;
        uint256 confirmations;
    }

    struct PegConfiguration {
        uint256 fixedFee;        // fee floor
        uint256 percentageFee;   // 10_000 = 100%
        uint256 penaltyFee;      // individual slash amount
        ConfirmationTier[] confirmationTiers; // sorted ascending by maxAmount
        uint256 callTime;        // LP action deadline
        uint256 expireTime;      // refund-enable; strictly later than callTime
        uint256 expireBlocks;
        uint256 deliveryGrace;   // tolerance added to callTime before an individual slash (S0.1 D4)
        uint256 minAmount;
        uint256 maxAmount;
    }

    // events omitted for brevity; one *Changed event per field, emitted on apply

    function getPegInConfiguration() external view returns (PegConfiguration memory);
    function getPegOutConfiguration() external view returns (PegConfiguration memory);

    function getRequiredPegInConfirmations(uint256 amount) external view returns (uint256);
    function getRequiredPegOutConfirmations(uint256 amount) external view returns (uint256);

    function calculatePegInFee(uint256 amount) external view returns (uint256);
    function calculatePegOutFee(uint256 amount) external view returns (uint256);

    // immutable, set at deployment
    function getPegInConfigurationBounds() external view returns (PegConfiguration memory min, PegConfiguration memory max);
    function getPegOutConfigurationBounds() external view returns (PegConfiguration memory min, PegConfiguration memory max);
}
```

Change from the proposal draft: added `deliveryGrace` to support the LP grace tolerance from the S0.1 late-delivery decision. `timeForDeposit` is dropped for the PoC because the commit-first model has no user deposit window.

## IPegInAddressRegistry

Registration is permissionless and deposit-gated per the S0.4 decision: any caller may register, gated by an SPV proof of a BTC deposit to the derived address. No ECDSA signature is required.

```solidity
interface IPegInAddressRegistry {
    enum Encoding { BASE58, BECH32, BECH32M }

    event AddressRegistered(address indexed addr, bytes32 indexed registrationRoot);

    // deposit-gated, permissionless: proof shows BTC was paid to the derived address
    function registerAddress(
        address addr,
        bytes calldata btcTx,
        uint256 blockHeight,
        bytes calldata merkleProof
    ) external;

    function getPegInAddress(address addr) external view returns (bytes memory, Encoding);
    function getPegInAddresses(address[] calldata addrs)
        external view returns (bytes[] memory derivationAddresses, Encoding encoding);

    function getRegistrationRoot() external view returns (bytes32);
    function isRegistered(address addr) external view returns (bool);
    function getRegistrationBlock(address addr) external view returns (uint256);
    function getRegistrationCount() external view returns (uint256);
}
```

Change from the proposal draft: `registerAddress` takes the SPV deposit proof rather than a bare address, with no signature parameter, per the permissionless deposit-gated decision.

## IPegOutEscrow

Matches the frozen state machine. Fulfillment with SPV proof and the refund paths execute against `PegOutContract`, reusing the existing peg-out logic.

```solidity
interface IPegOutEscrow {
    enum EscrowedPegOutState { REQUESTED, CLAIMED, CANCELLED, FULFILLED, REFUNDED }

    event PegOutRequested(bytes32 indexed quoteHash, address indexed refundAddress, uint256 indexed amount, bytes destinationAddress);
    event PegOutClaimed(address indexed lpAddress, bytes32 indexed quoteHash);
    event PegOutCancelled(bytes32 indexed quoteHash);

    function requestPegOut(bytes calldata destinationAddress, address refundAddress)
        external payable returns (bytes32 quoteHash);

    function cancelPegOut(bytes32 quoteHash) external;               // REQUESTED -> CANCELLED
    function claimPegOut(bytes32 quoteHash, bytes calldata signature) external; // REQUESTED -> CLAIMED
    function refundOnNoClaim(bytes32 quoteHash) external;            // REQUESTED -> REFUNDED + global slash

    function getPegOutState(bytes32 quoteHash) external view returns (EscrowedPegOutState);
}
```

Note: `refundPegOut(proof)` (`CLAIMED -> FULFILLED`) and `refundOnNoFulfill` (`CLAIMED -> REFUNDED` + individual slash) live on `PegOutContract`, which already holds the SPV and slashing logic, so they are not duplicated on the escrow interface.

## Reconciliation against the current split contracts

| Interface | New contract | Touches / reuses |
|---|---|---|
| `IFlyoverConfigurations` | `FlyoverConfigurations` (new, E1) | read by `PegInContract` (E4) and `PegOutContract` / escrow (E7) |
| `IPegInAddressRegistry` | `PegInAddressRegistry` (new, E2) | validated against `_bridge` for the deposit proof; watched by LPS (E5) |
| `IPegOutEscrow` | `PegOutEscrow` (new, E7) | moves RBTC into the existing `PegOutContract`; slashing via `CollateralManagement` (E3) |

Global slash and the registration grace window are added to `CollateralManagement` in E3 and are called by the peg-in claim (E4) and the escrow refund paths (E7).
