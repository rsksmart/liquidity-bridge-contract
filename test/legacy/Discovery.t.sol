// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DiscoveryTest is Test {
    LiquidityBridgeContractV2 public lbcImpl;
    ERC1967Proxy public lbcProxy;
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

    // Liquidity providers
    struct LiquidityProviderInfo {
        address signer;
        string name;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    LiquidityProviderInfo[] public liquidityProviders;

    uint256 constant LP_COLLATERAL = 1.5 ether;

    function setUp() public {
        lbcOwner = address(this);

        // Create test accounts (1-16 for regular accounts, last 3 for LPs)
        for (uint i = 1; i <= 19; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            vm.deal(account, 100 ether);
            if (i <= 16) {
                accounts.push(account);
            }
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy LiquidityBridgeContractV2
        lbcImpl = new LiquidityBridgeContractV2();
        bytes memory initData = abi.encodeWithSelector(
            LiquidityBridgeContractV2.initializeV2.selector
        );
        lbcProxy = new ERC1967Proxy(address(lbcImpl), initData);
        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Register 3 liquidity providers
        address lp1 = address(
            uint160(uint256(keccak256(abi.encodePacked("account", uint(17)))))
        );
        address lp2 = address(
            uint160(uint256(keccak256(abi.encodePacked("account", uint(18)))))
        );
        address lp3 = address(
            uint160(uint256(keccak256(abi.encodePacked("account", uint(19)))))
        );

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        vm.prank(lp1, lp1); // Set both msg.sender and tx.origin
        lbc.register{value: LP_COLLATERAL}(
            "First LP",
            "http://localhost/api1",
            true,
            "both"
        );

        vm.prank(lp2, lp2); // Set both msg.sender and tx.origin
        lbc.register{value: LP_COLLATERAL / 2}(
            "Second LP",
            "http://localhost/api2",
            true,
            "pegin"
        );

        vm.prank(lp3, lp3); // Set both msg.sender and tx.origin
        lbc.register{value: LP_COLLATERAL / 2}(
            "Third LP",
            "http://localhost/api3",
            true,
            "pegout"
        );

        liquidityProviders.push(
            LiquidityProviderInfo(
                lp1,
                "First LP",
                "http://localhost/api1",
                true,
                "both"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp2,
                "Second LP",
                "http://localhost/api2",
                true,
                "pegin"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp3,
                "Third LP",
                "http://localhost/api3",
                true,
                "pegout"
            )
        );
    }

    function test_ListRegisteredProviders() public view {
        LiquidityBridgeContractV2.LiquidityProvider[] memory providerList = lbc
            .getProviders();
        assertEq(providerList.length, 3);

        for (uint i = 0; i < providerList.length; i++) {
            assertEq(providerList[i].id, i + 1);
            assertEq(providerList[i].provider, liquidityProviders[i].signer);
            assertEq(providerList[i].name, liquidityProviders[i].name);
            assertEq(
                providerList[i].apiBaseUrl,
                liquidityProviders[i].apiBaseUrl
            );
            assertEq(providerList[i].status, liquidityProviders[i].status);
            assertEq(
                providerList[i].providerType,
                liquidityProviders[i].providerType
            );
        }
    }

    function test_GetLastProviderId() public view {
        uint256 lastProviderId = lbc.providerId();
        assertEq(lastProviderId, liquidityProviders.length);
    }

    function test_AllowProviderToDisableByItself() public {
        address lpSigner = liquidityProviders[1].signer;

        vm.prank(lpSigner);
        lbc.setProviderStatus(2, false);

        LiquidityBridgeContractV2.LiquidityProvider memory provider = lbc
            .getProvider(lpSigner);
        assertEq(provider.status, false);
    }

    function test_FailIfProviderDoesNotExist() public {
        address notLpSigner = accounts[0];

        // Verify it's not an LP
        bool isLp = false;
        for (uint i = 0; i < liquidityProviders.length; i++) {
            if (liquidityProviders[i].signer == notLpSigner) {
                isLp = true;
                break;
            }
        }
        assertEq(isLp, false);

        vm.expectRevert("LBC001");
        lbc.getProvider(notLpSigner);
    }

    function test_ReturnCorrectStateOfProvider() public {
        address lp1 = liquidityProviders[0].signer;
        address lp2 = liquidityProviders[1].signer;

        vm.prank(lp1);
        lbc.setProviderStatus(1, false);

        LiquidityBridgeContractV2.LiquidityProvider memory provider = lbc
            .getProvider(lp1);
        assertEq(provider.status, false);
        assertEq(provider.name, "First LP");
        assertEq(provider.apiBaseUrl, "http://localhost/api1");
        assertEq(provider.provider, lp1);
        assertEq(provider.providerType, "both");

        provider = lbc.getProvider(lp2);
        assertEq(provider.status, true);
        assertEq(provider.name, "Second LP");
        assertEq(provider.apiBaseUrl, "http://localhost/api2");
        assertEq(provider.provider, lp2);
        assertEq(provider.providerType, "pegin");
    }

    function test_AllowProviderToEnableByItself() public {
        address lpSigner = liquidityProviders[1].signer;

        vm.prank(lpSigner);
        lbc.setProviderStatus(2, false);
        LiquidityBridgeContractV2.LiquidityProvider memory provider = lbc
            .getProvider(lpSigner);
        assertEq(provider.status, false);

        vm.prank(lpSigner);
        lbc.setProviderStatus(2, true);
        provider = lbc.getProvider(lpSigner);
        assertEq(provider.status, true);
    }

    function test_DisableAndEnableProviderAsLBCOwner() public {
        address lpSigner = liquidityProviders[1].signer;

        vm.prank(lbcOwner);
        lbc.setProviderStatus(2, false);
        LiquidityBridgeContractV2.LiquidityProvider memory provider = lbc
            .getProvider(lpSigner);
        assertEq(provider.status, false);

        vm.prank(lbcOwner);
        lbc.setProviderStatus(2, true);
        provider = lbc.getProvider(lpSigner);
        assertEq(provider.status, true);
    }

    function test_FailDisablingProviderAsNonOwners() public {
        address lpSigner = liquidityProviders[0].signer; // provider id 1

        vm.prank(lpSigner);
        vm.expectRevert("LBC005");
        lbc.setProviderStatus(2, false); // trying to modify provider id 2
    }

    function test_UpdateLiquidityProviderInformationCorrectly() public {
        uint providerIndex = 1;
        address providerSigner = liquidityProviders[providerIndex].signer;

        LiquidityBridgeContractV2.LiquidityProvider[] memory providers = lbc
            .getProviders();
        LiquidityBridgeContractV2.LiquidityProvider memory provider = providers[
            providerIndex
        ];

        // Store initial state
        uint initialId = provider.id;
        address initialProvider = provider.provider;
        bool initialStatus = provider.status;
        string memory initialProviderType = provider.providerType;
        string memory initialName = provider.name;
        string memory initialApiBaseUrl = provider.apiBaseUrl;

        string memory newName = "modified name";
        string memory newApiBaseUrl = "https://modified.com";

        vm.prank(providerSigner);
        vm.expectEmit(true, false, false, true);
        emit LiquidityBridgeContractV2.ProviderUpdate(
            providerSigner,
            newName,
            newApiBaseUrl
        );
        lbc.updateProvider(newName, newApiBaseUrl);

        providers = lbc.getProviders();
        provider = providers[providerIndex];

        // Verify unchanged fields
        assertEq(provider.id, initialId);
        assertEq(provider.provider, initialProvider);
        assertEq(provider.status, initialStatus);
        assertEq(provider.providerType, initialProviderType);

        // Verify changed fields
        assertTrue(
            keccak256(bytes(provider.name)) != keccak256(bytes(initialName))
        );
        assertTrue(
            keccak256(bytes(provider.apiBaseUrl)) !=
                keccak256(bytes(initialApiBaseUrl))
        );
        assertEq(provider.name, newName);
        assertEq(provider.apiBaseUrl, newApiBaseUrl);
    }

    function test_FailIfUnregisteredProviderUpdatesHisInformation() public {
        address provider = accounts[5];
        string memory newName = "not-existing name";
        string memory newApiBaseUrl = "https://not-existing.com";

        vm.prank(provider);
        vm.expectRevert("LBC001");
        lbc.updateProvider(newName, newApiBaseUrl);
    }

    function test_FailIfProviderMakesUpdateWithInvalidInformation() public {
        address provider = liquidityProviders[2].signer;
        string memory newName = "any name";
        string memory newApiBaseUrl = "https://any.com";

        vm.prank(provider);
        vm.expectRevert("LBC076");
        lbc.updateProvider("", newApiBaseUrl);

        vm.prank(provider);
        vm.expectRevert("LBC076");
        lbc.updateProvider(newName, "");
    }

    function test_ListEnabledAndNotResignedProvidersOnly() public {
        /**
         * Target provider statuses per account:
         * accounts array indices:
         * 0 - active (LP 4)
         * 1 - not a provider
         * 2 - resigned and disabled (LP 5)
         * 3 - disabled (LP 6)
         * 4 - active (LP 7)
         * 5 - resigned but active (LP 8)
         *
         * Original LPs array (0,1,2):
         * 0 - active (LP 1)
         * 1 - disabled (LP 2)
         * 2 - active (LP 3)
         */

        // Disable LP 2
        vm.prank(liquidityProviders[1].signer);
        lbc.setProviderStatus(2, false);

        // Register 5 new LPs (accounts 0, 2, 3, 4, 5)
        uint[5] memory newLpIndices = [uint(0), 2, 3, 4, 5];

        for (uint i = 0; i < newLpIndices.length; i++) {
            uint accountIdx = newLpIndices[i];
            vm.prank(accounts[accountIdx], accounts[accountIdx]); // Set both msg.sender and tx.origin
            lbc.register{value: LP_COLLATERAL}(
                string.concat("LP account ", vm.toString(accountIdx)),
                string.concat(
                    "http://localhost/api-account",
                    vm.toString(accountIdx)
                ),
                true,
                "both"
            );
        }

        // LP 5 (account 2): resign and disable
        vm.prank(accounts[2]);
        lbc.setProviderStatus(5, false);
        vm.prank(accounts[2]);
        lbc.resign();

        // LP 6 (account 3): disable
        vm.prank(accounts[3]);
        lbc.setProviderStatus(6, false);

        // LP 8 (account 5): resign but keep active
        vm.prank(accounts[5]);
        lbc.resign();

        // Get providers list
        LiquidityBridgeContractV2.LiquidityProvider[] memory result = lbc
            .getProviders();

        // Should only show 4 providers: LP1, LP3, LP4, LP7
        assertEq(result.length, 4);

        // Verify LP1
        assertEq(result[0].id, 1);
        assertEq(result[0].provider, liquidityProviders[0].signer);
        assertEq(result[0].name, "First LP");
        assertEq(result[0].apiBaseUrl, "http://localhost/api1");
        assertEq(result[0].status, true);
        assertEq(result[0].providerType, "both");

        // Verify LP3
        assertEq(result[1].id, 3);
        assertEq(result[1].provider, liquidityProviders[2].signer);
        assertEq(result[1].name, "Third LP");
        assertEq(result[1].apiBaseUrl, "http://localhost/api3");
        assertEq(result[1].status, true);
        assertEq(result[1].providerType, "pegout");

        // Verify LP4 (account 0)
        assertEq(result[2].id, 4);
        assertEq(result[2].provider, accounts[0]);
        assertEq(result[2].name, "LP account 0");
        assertEq(result[2].apiBaseUrl, "http://localhost/api-account0");
        assertEq(result[2].status, true);
        assertEq(result[2].providerType, "both");

        // Verify LP7 (account 4)
        assertEq(result[3].id, 7);
        assertEq(result[3].provider, accounts[4]);
        assertEq(result[3].name, "LP account 4");
        assertEq(result[3].apiBaseUrl, "http://localhost/api-account4");
        assertEq(result[3].status, true);
        assertEq(result[3].providerType, "both");
    }

    function test_ShouldReuseSameIdAndReturnCurrentEntryAfterReRegistration()
        public
    {
        address lp = liquidityProviders[0].signer;

        vm.prank(lp);
        lbc.resign();

        vm.prank(lp);
        lbc.withdrawCollateral();

        vm.prank(lp, lp);
        uint returnedId = lbc.register{value: LP_COLLATERAL / 2}(
            "First LP Re",
            "http://localhost/api1-re",
            true,
            "pegin"
        );

        assertEq(returnedId, 1);
        assertEq(lbc.providerId(), 3);

        LiquidityBridgeContractV2.LiquidityProvider memory provider = lbc
            .getProvider(lp);
        assertEq(provider.id, 1);
        assertEq(
            keccak256(bytes(provider.name)),
            keccak256(bytes("First LP Re"))
        );
        assertEq(
            keccak256(bytes(provider.apiBaseUrl)),
            keccak256(bytes("http://localhost/api1-re"))
        );
        assertEq(
            keccak256(bytes(provider.providerType)),
            keccak256(bytes("pegin"))
        );

        vm.prank(lp);
        lbc.updateProvider("First LP Final", "http://localhost/api1-final");

        provider = lbc.getProvider(lp);
        assertEq(provider.id, 1);
        assertEq(
            keccak256(bytes(provider.name)),
            keccak256(bytes("First LP Final"))
        );
        assertEq(
            keccak256(bytes(provider.apiBaseUrl)),
            keccak256(bytes("http://localhost/api1-final"))
        );
        assertEq(
            keccak256(bytes(provider.providerType)),
            keccak256(bytes("pegin"))
        );
    }
}
