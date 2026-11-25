// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {RecordingDestination} from "./CallDestinationMocks.sol";

/// @notice Setup and helpers shared by the requestPegIn contract-call unit and fuzz tests
abstract contract RequestPegInContractCallTestBase is ResolvePegInTestBase {
    uint32 internal constant CALL_GAS = 100_000;
    uint256 internal constant GAS_PRICE = 0.06 gwei;
    bytes internal constant CALL_DATA = hex"d0e30db0"; // deposit()

    RecordingDestination internal recorder;

    function setUp() public override {
        super.setUp();
        configurations.setClaimGasFee(CLAIM_GAS_FEE);
        recorder = new RecordingDestination();
        vm.txGasPrice(GAS_PRICE);
    }

    // ---- helpers ----

    function _expected() internal pure returns (uint256) {
        return DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT) - CLAIM_GAS_FEE;
    }

    /// @dev The requested gas plus the 2,300-gas stipend, times the gas price
    function _gasFee(
        uint256 gasLimit,
        uint256 gasPrice
    ) internal pure returns (uint256) {
        return (gasLimit + 2300) * gasPrice;
    }

    /// @dev What the LP fronts and the destination receives
    function _netToUser(
        uint256 gasLimit,
        uint256 gasPrice
    ) internal pure returns (uint256) {
        return _expected() - _gasFee(gasLimit, gasPrice);
    }

    function _callTx(
        address destination,
        uint32 maxGasLimit
    ) internal view returns (bytes memory) {
        return
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                destination,
                maxGasLimit,
                CALL_DATA
            );
    }

    function _claimSuccess(bytes32 pegInId) internal view returns (bool) {
        return
            (uint256(
                vm.load(address(pegInContract), bytes32(_claimSlot(pegInId)))
            ) >> 160) &
                0xff ==
            1;
    }
}
