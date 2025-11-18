// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title OwnableDaoContributorUpgradeable
/// @notice This contract is used to handle the contributions to the DAO
/// @author Rootstock Labs
/// @dev Any contract that inherits from this contract will be able to collect DAO
/// contributions according to the logic the child contract defines
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

    /// @notice This event is emitted when a contribution is made to the DAO
    /// @param contributor the address of the contributor
    /// @param amount the amount of the contribution
    event DaoContribution(address indexed contributor, uint256 indexed amount);

    /// @notice This event is emitted when the DAO fees are claimed. The claim is always all the
    /// contributions made to the DAO by this contract so far
    /// @param claimer the address of the claimer
    /// @param receiver the address of the receiver
    /// @param amount the amount of the fees claimed
    event DaoFeesClaimed(address indexed claimer, address indexed receiver, uint256 indexed amount);

    /// @notice This event is emitted when the contributions are configured
    /// @param feeCollector the address of the fee collector
    /// @param feePercentage the percentage of the contributions that goes to the DAO
    event ContributionsConfigured(address indexed feeCollector, uint256 indexed feePercentage);

    /// @notice This error is emitted when there are no fees to claim
    error NoFees();

    /// @notice This error is emitted when the fee collector is not set
    error FeeCollectorUnset();

    /// @notice This function is used to claim the contributions to the DAO.
    /// It sends to the fee collector all the accumulated contributions so far
    /// and resets the accumulated contributions to zero
    /// @dev The function is only callable by the owner of the contract
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

    /// @notice This function is used to configure the contributions to the DAO
    /// @param feeCollector the address of the fee collector
    /// @param feePercentage the percentage of the contributions that goes to the DAO
    /// @dev The function is only callable by the owner of the contract
    function configureContributions(
        address payable feeCollector,
        uint256 feePercentage
    ) external onlyOwner {
        DaoContributorStorage storage $ = _getContributorStorage();
        $.feeCollector = feeCollector;
        $.feePercentage = feePercentage;
        emit ContributionsConfigured(feeCollector, feePercentage);
    }

    /// @notice This function is used to get the fee percentage
    /// that the child contracts use to calculate the contributions
    /// @return feePercentage the fee percentage
    function getFeePercentage() external view returns (uint256) {
        return _getContributorStorage().feePercentage;
    }

    /// @notice This function is used to get the current contribution
    /// @return currentContribution the current contribution
    function getCurrentContribution() external view returns (uint256) {
        return _getContributorStorage().currentContribution;
    }

    /// @notice This function is used to get the fee collector
    /// @return feeCollector the fee collector address
    function getFeeCollector() external view returns (address) {
        return _getContributorStorage().feeCollector;
    }

    /// @notice This function is used to initialize the contract
    /// @param owner the owner of the contract
    /// @param feePercentage the percentage that the child contracts use to calculate the contributions
    /// @param feeCollector the address of the fee collector that will receive the contributions
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

    /// @notice This function is used to add a contribution to the DAO
    /// @dev The function is only callable by the child contract, it can be
    /// included wherever they consider the protocol should collect fees for the DAO
    /// @param contributor the address of the contributor
    /// @param amount the amount of the contribution
    function _addDaoContribution(address contributor, uint256 amount) internal {
        if (amount < 1) return;
        DaoContributorStorage storage $ = _getContributorStorage();
        $.currentContribution += amount;
        emit DaoContribution(contributor, amount);
    }

    /// @dev The function is used to get the storage of the contract, avoid using the regular
    /// storage to prevent conflicts with state variables of the child contract
    /// @return $ the contributor storage
    function _getContributorStorage() private pure returns (DaoContributorStorage storage $) {
        assembly {
            $.slot := _CONTRIBUTOR_STORAGE_LOCATION
        }
    }
}
