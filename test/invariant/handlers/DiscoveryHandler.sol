// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {FlyoverDiscovery} from "../../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title Discovery Invariant Handler
/// @notice Provides fuzzable handler functions for FlyoverDiscovery invariant testing
contract DiscoveryHandler is HandlerBase {
    FlyoverDiscovery public discovery;
    CollateralManagementContract public collateralManagement;
    address public owner;

    struct ProviderInfo {
        address addr;
        uint256 providerId;
        Flyover.ProviderType providerType;
        bool statusSet;
    }

    ProviderInfo[] public registeredProviders;

    uint256 public ghost_totalRegistered;
    uint256 public ghost_lastProviderId;

    constructor(
        FlyoverDiscovery discovery_,
        CollateralManagementContract collateralManagement_,
        address owner_
    ) {
        discovery = discovery_;
        collateralManagement = collateralManagement_;
        owner = owner_;
    }

    function registerProvider(
        uint256 seed,
        uint8 providerTypeSeed,
        uint256 extraCollateral
    ) external {
        handlerCalls["registerProvider"] += 1;

        Flyover.ProviderType providerType = _getProviderType(providerTypeSeed);
        uint256 requiredCollateral = _getRequiredCollateral(providerType);
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = requiredCollateral + extraCollateral;

        address provider = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encode(seed, ghost_totalRegistered, block.timestamp)
                    )
                )
            )
        );
        vm.deal(provider, collateral + 1 ether);

        string memory name = _generateName(seed);
        string memory url = _generateUrl(seed);

        vm.prank(provider, provider);
        try
            discovery.register{value: collateral}(name, url, true, providerType)
        returns (uint256 id) {
            vm.prank(owner);
            discovery.approveRegistration(provider);
            ghost_totalRegistered++;
            ghost_lastProviderId = id;
            registeredProviders.push(
                ProviderInfo({
                    addr: provider,
                    providerId: id,
                    providerType: providerType,
                    statusSet: true
                })
            );
        } catch {}
    }

    function toggleStatus(uint256 providerSeed, bool status) external {
        handlerCalls["toggleStatus"] += 1;

        if (registeredProviders.length == 0) return;

        uint256 idx = providerSeed % registeredProviders.length;
        ProviderInfo storage info = registeredProviders[idx];

        vm.prank(info.addr);
        try discovery.setProviderStatus(info.providerId, status) {
            info.statusSet = status;
        } catch {}
    }

    function updateProviderInfo(
        uint256 providerSeed,
        uint256 nameSeed,
        uint256 urlSeed
    ) external {
        handlerCalls["updateProviderInfo"] += 1;

        if (registeredProviders.length == 0) return;

        uint256 idx = providerSeed % registeredProviders.length;
        ProviderInfo storage info = registeredProviders[idx];

        string memory name = _generateName(nameSeed);
        string memory url = _generateUrl(urlSeed);

        vm.prank(info.addr);
        try discovery.updateProvider(name, url) {} catch {}
    }

    function getRegisteredCount() external view returns (uint256) {
        return registeredProviders.length;
    }

    function getProviderInfo(
        uint256 idx
    )
        external
        view
        returns (
            address addr,
            uint256 providerId,
            Flyover.ProviderType providerType,
            bool statusSet
        )
    {
        ProviderInfo storage info = registeredProviders[idx];
        return (info.addr, info.providerId, info.providerType, info.statusSet);
    }
}
