// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Flyover} from "./libraries/Flyover.sol";

abstract contract OwnableDaoContributorUpgradeable is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable {

    // @custom:storage-location erc7201:rsk.dao.contributor
    struct DaoContributorStorage {
        uint256 feePercentage;
        uint256 currentContribution;
        address payable feeCollector;
    }

    // keccak256(abi.encode(uint256(keccak256(bytes("rsk.dao.contributor"))) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _CONTRIBUTOR_STORAGE_LOCATION =
        0xb7e513d124139aa68259a99d4c2c344f3ba61e36716330d77f7fa887d0048e00;

    event DaoContribution(address indexed contributor, uint256 indexed amount);
    event DaoFeesClaimed(address indexed claimer, address indexed receiver, uint256 indexed amount);
    event ContributionsConfigured(address indexed feeCollector, uint256 indexed feePercentage);

    error NoFees();
    error FeeCollectorUnset();

    function claimContribution() external onlyOwner nonReentrant {
        DaoContributorStorage storage $ = _getContributorStorage();
        uint256 amount = $.currentContribution;
        $.currentContribution = 0;
        address feeCollector = $.feeCollector;
        if (amount == 0) revert NoFees();
        if (feeCollector == address(0)) revert FeeCollectorUnset();
        if (amount > address(this).balance) revert Flyover.NoBalance(amount, address(this).balance);
        emit DaoFeesClaimed(msg.sender, feeCollector, amount);
        (bool sent, bytes memory reason) = feeCollector.call{value: amount}("");
        if (!sent) revert Flyover.PaymentFailed(feeCollector, amount, reason);
    }

    function configureContributions(
        address payable feeCollector,
        uint256 feePercentage
    ) external onlyOwner {
        DaoContributorStorage storage $ = _getContributorStorage();
        $.feeCollector = feeCollector;
        $.feePercentage = feePercentage;
        emit ContributionsConfigured(feeCollector, feePercentage);
    }

    function getFeePercentage() external view returns (uint256) {
        return _getContributorStorage().feePercentage;
    }

    function getCurrentContribution() external view returns (uint256) {
        return _getContributorStorage().currentContribution;
    }

    function getFeeCollector() external view returns (address) {
        return _getContributorStorage().feeCollector;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __OwnableDaoContributor_init(
        address owner,
        uint256 feePercentage,
        address payable feeCollector
    ) internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
        __Ownable_init_unchained(owner);
        DaoContributorStorage storage $ = _getContributorStorage();
        $.feePercentage = feePercentage;
        $.feeCollector = feeCollector;
    }

    function _addDaoContribution(address contributor, uint256 amount) internal {
        if (amount < 1) return;
        DaoContributorStorage storage $ = _getContributorStorage();
        $.currentContribution += amount;
        emit DaoContribution(contributor, amount);
    }

    function _getContributorStorage() private pure returns (DaoContributorStorage storage $) {
        assembly {
            $.slot := _CONTRIBUTOR_STORAGE_LOCATION
        }
    }
}
