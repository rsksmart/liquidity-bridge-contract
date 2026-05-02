// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */
import {IFlyoverDiscovery} from "../interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../libraries/Flyover.sol";

contract RegisterCaller {
    function callRegister(
        address discovery,
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        Flyover.ProviderType providerType
    ) external payable {
        IFlyoverDiscovery(discovery).register{value: msg.value}(
            name,
            apiBaseUrl,
            status,
            providerType
        );
    }

    function callRegisterWithTypeUint(
        address discovery,
        string calldata name,
        string calldata apiBaseUrl,
        bool status,
        uint256 providerTypeRaw
    ) external payable {
        IFlyoverDiscovery(discovery).register{value: msg.value}(
            name,
            apiBaseUrl,
            status,
            Flyover.ProviderType(providerTypeRaw)
        );
    }
}
