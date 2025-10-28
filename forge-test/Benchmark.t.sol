// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CollateralManagementContract} from "../contracts/CollateralManagement.sol";
import {FlyoverDiscovery} from "../contracts/FlyoverDiscovery.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../contracts/libraries/Flyover.sol";

contract BenchmarkTest is Test {
    CollateralManagementContract public collateralManagementImpl;
    ERC1967Proxy public collateralManagementProxy;
    CollateralManagementContract public collateralManagement;

    FlyoverDiscovery public discoveryImpl;
    ERC1967Proxy public discoveryProxy;
    FlyoverDiscovery public discovery;

    address public owner;
    address[] public accounts;

    function setUp() public {
        owner = address(this);

        // Create test accounts
        for (uint i = 1; i <= 5; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            accounts.push(account);
            vm.deal(account, 100 ether);
        }

        // Deploy CollateralManagementContract
        collateralManagementImpl = new CollateralManagementContract();
        bytes memory collateralInitData = abi.encodeWithSelector(
            CollateralManagementContract.initialize.selector,
            owner,
            5000,
            0.03 ether,
            60,
            10
        );
        collateralManagementProxy = new ERC1967Proxy(
            address(collateralManagementImpl),
            collateralInitData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(collateralManagementProxy))
        );

        // Deploy FlyoverDiscovery
        discoveryImpl = new FlyoverDiscovery();
        bytes memory discoveryInitData = abi.encodeWithSelector(
            FlyoverDiscovery.initialize.selector,
            owner,
            5000,
            address(collateralManagement)
        );
        discoveryProxy = new ERC1967Proxy(
            address(discoveryImpl),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        // Grant COLLATERAL_ADDER role
        bytes32 collateralAdder = collateralManagement.COLLATERAL_ADDER();
        collateralManagement.grantRole(collateralAdder, address(discovery));
    }

    function test_RegisterAndFetchLPOfEachType() public {
        // Provider data matching the TypeScript test
        ProviderData[5] memory providersData = [
            ProviderData({
                account: accounts[0],
                providerType: Flyover.ProviderType.Both,
                apiBaseUrl: "https://api.flyover1.com",
                name: "Flyover1"
            }),
            ProviderData({
                account: accounts[1],
                providerType: Flyover.ProviderType.PegIn,
                apiBaseUrl: "https://api.flyover2.com",
                name: "Flyover2"
            }),
            ProviderData({
                account: accounts[2],
                providerType: Flyover.ProviderType.PegOut,
                apiBaseUrl: "https://api.flyover3.com",
                name: "Flyover3"
            }),
            ProviderData({
                account: accounts[3],
                providerType: Flyover.ProviderType.Both,
                apiBaseUrl: "https://api.flyover4.com",
                name: "Flyover4"
            }),
            ProviderData({
                account: accounts[4],
                providerType: Flyover.ProviderType.Both,
                apiBaseUrl: "https://api.flyover5.com",
                name: "Flyover5"
            })
        ];

        // Register all providers
        for (uint i = 0; i < providersData.length; i++) {
            ProviderData memory providerData = providersData[i];

            vm.prank(providerData.account);
            discovery.register{value: 0.06 ether}(
                providerData.name,
                providerData.apiBaseUrl,
                true,
                providerData.providerType
            );
        }

        console.log(
            "-------------------------------- GET PROVIDERS --------------------------------"
        );
        Flyover.LiquidityProvider[] memory discoveryProviders = discovery
            .getProviders();
        for (uint i = 0; i < discoveryProviders.length; i++) {
            console.log("Provider", i);
            console.log("  id:", discoveryProviders[i].id);
            console.log("  name:", discoveryProviders[i].name);
            console.log(
                "  providerAddress:",
                discoveryProviders[i].providerAddress
            );
            console.log("  apiBaseUrl:", discoveryProviders[i].apiBaseUrl);
            console.log("  status:", discoveryProviders[i].status);
            console.log(
                "  providerType:",
                uint(discoveryProviders[i].providerType)
            );
            console.log("");
        }

        console.log(
            "-------------------------------- GET PROVIDER --------------------------------"
        );
        for (uint i = 0; i < providersData.length; i++) {
            Flyover.LiquidityProvider memory result = discovery.getProvider(
                providersData[i].account
            );
            console.log("Provider:", providersData[i].name);
            console.log("  id:", result.id);
            console.log("  name:", result.name);
            console.log("  providerAddress:", result.providerAddress);
            console.log("  apiBaseUrl:", result.apiBaseUrl);
            console.log("  status:", result.status);
            console.log("  providerType:", uint(result.providerType));
            console.log("");
        }

        console.log(
            "-------------------------------- IS OPERATIONAL --------------------------------"
        );
        for (uint i = 0; i < providersData.length; i++) {
            bool result = discovery.isOperational(
                providersData[i].providerType,
                providersData[i].account
            );
            console.log(providersData[i].name, "operational:", result);
        }
    }

    struct ProviderData {
        address account;
        Flyover.ProviderType providerType;
        string apiBaseUrl;
        string name;
    }
}
