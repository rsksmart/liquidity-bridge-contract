// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ICollateralManagement} from "../interfaces/ICollateralManagement.sol";
import {Flyover} from "../libraries/Flyover.sol";
import {Quotes} from "../libraries/Quotes.sol";

/* solhint-disable comprehensive-interface */
contract CollateralManagementMock is ICollateralManagement {

    uint256 private _balance;

    function addPegInCollateralTo(address) external payable {
        _balance += msg.value;
    }

    function addPegInCollateral() external payable {
        _balance += msg.value;
    }

    function addPegOutCollateralTo(address) external payable {
        _balance += msg.value;
    }

    function addPegOutCollateral() external payable {
        _balance += msg.value;
    }

    function slashPegInCollateral(address, Quotes.PegInQuote calldata, bytes32) external {
        emit Penalized(address(0), bytes32(0), Flyover.ProviderType.PegOut, 0, 0);
    }

    function slashPegOutCollateral(address, Quotes.PegOutQuote calldata, bytes32) external {
        emit Penalized(address(0), bytes32(0), Flyover.ProviderType.PegOut, 0, 0);
    }

    function getPegInCollateral(address) external pure returns (uint256) {
        return 10 ether;
    }

    function getPegOutCollateral(address) external pure returns (uint256) {
        return 10 ether;
    }

    function getResignationBlock(address) external pure returns (uint256) {
        return 0;
    }

    function getMinCollateral() external pure returns (uint256) {
        return 0.006 ether;
    }

    function isRegistered(Flyover.ProviderType, address) external pure returns (bool) {
        return true;
    }

    function isCollateralSufficient(Flyover.ProviderType, address) external pure returns (bool) {
        return true;
    }
}
/* solhint-enable comprehensive-interface */
