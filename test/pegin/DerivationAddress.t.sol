// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {IPegIn} from "../../src/interfaces/IPegIn.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DerivationAddress Tests
/// @notice Tests for PegIn BTC deposit address derivation and validation
contract DerivationAddressTest is Test {
    // Test constants
    // CollateralManagement constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 0;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD = 2300 * 65164000;
    uint256 constant TEST_MIN_PEGIN = 0.5 ether;

    address constant ZERO_ADDRESS = address(0);

    // Discovery constants
    uint48 constant DISCOVERY_INITIAL_DELAY = 0;

    // Shared BTC addresses for test quotes
    bytes20 constant FED_BTC_ADDRESS =
        bytes20(hex"a157fd1a536371656f3c19c2005199308a49bc9c");
    bytes constant LP_BTC_ADDRESS_MAINNET =
        hex"00840098213fec4001cdc4a77cc3340f5bb83d9ed5";
    bytes constant LP_BTC_ADDRESS_TESTNET =
        hex"6f840098213fec4001cdc4a77cc3340f5bb83d9ed5";
    bytes constant BTC_REFUND_ADDRESS_MAINNET =
        hex"000000000000000000000000000000000000000000";
    bytes constant BTC_REFUND_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";

    // Deposit addresses (mainnet and testnet for each test case)
    bytes constant MAINNET_DEPOSIT_ADDRESS_1 =
        hex"0551e9a3af3e3ee3e82623092779c6bf2f6842bdfb265747e8";
    bytes constant TESTNET_DEPOSIT_ADDRESS_1 =
        hex"c4291a9564b48c8e6871ceaaae2673b7d47afbab75a97b1e54";
    bytes constant MAINNET_DEPOSIT_ADDRESS_2 =
        hex"0533a3241448538400b4126bda482a70ec99f9dba60130cdd1";
    bytes constant TESTNET_DEPOSIT_ADDRESS_2 =
        hex"c4e224d91e0a8e31b9d814476ad4a23938ac16d23df79452b6";
    bytes constant MAINNET_DEPOSIT_ADDRESS_3 =
        hex"05ed352bccc4344b145b6739593c65a1eaa673bcfc79808a91";
    bytes constant TESTNET_DEPOSIT_ADDRESS_3 =
        hex"c450f741e356eb218b8b8fca751ad51c3bdd523f8bb058a8d5";

    address owner = address(1);
    PauseRegistry internal _pauseRegistry;

    // Foundry deterministic deployment addresses (with real CollateralManagement)
    address constant FOUNDRY_MAINNET_CONTRACT =
        0x03A6a84cD762D9707A21605b548aaaB891562aAb;
    address constant FOUNDRY_TESTNET_CONTRACT =
        0x03A6a84cD762D9707A21605b548aaaB891562aAb;

    // ============ hashPegInQuote function tests ============

    function test_HashPegInQuote_RevertsIfQuoteBelongsToOtherContract() public {
        PegInContract pegIn = deployPegInContract(true);

        Quotes.PegInQuote memory quote = createTestQuote1(address(pegIn), true);
        quote.lbcAddress = address(0x123); // Wrong contract address

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                address(pegIn),
                address(0x123)
            )
        );
        pegIn.hashPegInQuote(quote);
    }

    function test_HashPegInQuote_IsDeterministic() public {
        PegInContract pegIn = deployPegInContract(true);

        Quotes.PegInQuote memory quote = createTestQuote1(address(pegIn), true);

        bytes32 hash1 = pegIn.hashPegInQuote(quote);
        bytes32 hash2 = pegIn.hashPegInQuote(quote);

        assertEq(
            hash1,
            hash2,
            "Hashing the same quote should produce the same hash"
        );
    }

    // ============ validatePegInDepositAddress function tests ============

    function test_ValidatePegInDepositAddress_ValidatesMainnetAddresses()
        public
    {
        // chainId 30 matches the fixtures used to derive MAINNET_DEPOSIT_ADDRESS_*
        vm.chainId(30);
        PegInContract pegInMainnet = deployPegInContract(true);

        // Verify it deployed to the expected address
        assertEq(
            address(pegInMainnet),
            FOUNDRY_MAINNET_CONTRACT,
            "Contract should deploy deterministically"
        );

        // Test Case 1: nonce 3635227228603468300
        Quotes.PegInQuote memory quote1 = createTestQuote1(
            address(pegInMainnet),
            true
        );
        bool result1 = pegInMainnet.validatePegInDepositAddress(
            quote1,
            MAINNET_DEPOSIT_ADDRESS_1
        );
        assertTrue(result1, "Should validate mainnet address 1");

        // Test Case 2: nonce 6080686644105603000
        Quotes.PegInQuote memory quote2 = createTestQuote2(
            address(pegInMainnet),
            true
        );
        bool result2 = pegInMainnet.validatePegInDepositAddress(
            quote2,
            MAINNET_DEPOSIT_ADDRESS_2
        );
        assertTrue(result2, "Should validate mainnet address 2");

        // Test Case 3: nonce 7756734892733337000
        Quotes.PegInQuote memory quote3 = createTestQuote3(
            address(pegInMainnet),
            true
        );
        bool result3 = pegInMainnet.validatePegInDepositAddress(
            quote3,
            MAINNET_DEPOSIT_ADDRESS_3
        );
        assertTrue(result3, "Should validate mainnet address 3");
    }

    function test_ValidatePegInDepositAddress_ValidatesTestnetAddresses()
        public
    {
        // Deploy testnet contract
        PegInContract pegInTestnet = deployPegInContract(false);

        // Verify contracts deployed successfully to the expected address
        assertEq(
            address(pegInTestnet),
            FOUNDRY_TESTNET_CONTRACT,
            "Contract should deploy deterministically"
        );

        // Test Case 1: nonce 3635227228603468300
        Quotes.PegInQuote memory quote1 = createTestQuote1(
            address(pegInTestnet),
            false
        );
        bool result1 = pegInTestnet.validatePegInDepositAddress(
            quote1,
            TESTNET_DEPOSIT_ADDRESS_1
        );
        assertTrue(result1, "Should validate testnet address 1");

        // Test Case 2: nonce 6080686644105603000
        Quotes.PegInQuote memory quote2 = createTestQuote2(
            address(pegInTestnet),
            false
        );
        bool result2 = pegInTestnet.validatePegInDepositAddress(
            quote2,
            TESTNET_DEPOSIT_ADDRESS_2
        );
        assertTrue(result2, "Should validate testnet address 2");

        // Test Case 3: nonce 7756734892733337000
        Quotes.PegInQuote memory quote3 = createTestQuote3(
            address(pegInTestnet),
            false
        );
        bool result3 = pegInTestnet.validatePegInDepositAddress(
            quote3,
            TESTNET_DEPOSIT_ADDRESS_3
        );
        assertTrue(result3, "Should validate testnet address 3");
    }

    // ============ Helper Functions ============

    function deployPegInContract(
        bool mainnet
    ) internal returns (PegInContract) {
        // Deploy dependencies
        CollateralManagementContract collateralManagement = deployCollateralManagement();
        BridgeMock bridgeMock = new BridgeMock();

        // Deploy PegInContract
        PegInContract implementation = new PegInContract();

        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                TEST_MIN_PEGIN,
                address(collateralManagement),
                mainnet, // mainnet flag
                _pauseRegistry
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        return PegInContract(payable(address(proxy)));
    }

    function deployCollateralManagement()
        internal
        returns (CollateralManagementContract)
    {
        // Deploy PauseRegistry
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        _pauseRegistry = PauseRegistry(payable(address(prProxy)));

        // Deploy CollateralManagement first (matching PegInTestBase pattern)
        CollateralManagementContract cmImplementation = new CollateralManagementContract();
        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE,
                _pauseRegistry
            )
        );

        ERC1967Proxy cmProxy = new ERC1967Proxy(
            address(cmImplementation),
            cmInitData
        );

        CollateralManagementContract cm = CollateralManagementContract(
            payable(address(cmProxy))
        );

        // Deploy Discovery and grant it the COLLATERAL_ADDER role
        FlyoverDiscovery discoveryImplementation = new FlyoverDiscovery();
        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                owner,
                uint48(DISCOVERY_INITIAL_DELAY),
                address(cm),
                _pauseRegistry
            )
        );

        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImplementation),
            discoveryInitData
        );

        // Grant COLLATERAL_ADDER role to Discovery
        bytes32 collateralAdderRole = cm.COLLATERAL_ADDER();
        vm.prank(owner);
        cm.grantRole(collateralAdderRole, address(discoveryProxy));

        return cm;
    }

    // ============ Test Quote Helpers ============

    /// @notice Creates test quote 1 (nonce: 3635227228603468300)
    function createTestQuote1(
        address lbcAddress,
        bool mainnet
    ) internal view returns (Quotes.PegInQuote memory) {
        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 985215170000000000,
                gasFee: 547377600000,
                fedBtcAddress: FED_BTC_ADDRESS,
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 3635227228603468300,
                gasLimit: 21000,
                agreementTimestamp: 1752739488,
                timeForDeposit: 5400,
                callTime: 7200,
                depositConfirmations: 3,
                callOnRegister: false,
                btcRefundAddress: mainnet
                    ? BTC_REFUND_ADDRESS_MAINNET
                    : BTC_REFUND_ADDRESS_TESTNET,
                liquidityProviderBtcAddress: mainnet
                    ? LP_BTC_ADDRESS_MAINNET
                    : LP_BTC_ADDRESS_TESTNET,
                data: new bytes(0)
            });
    }

    /// @notice Creates test quote 2 (nonce: 6080686644105603000)
    function createTestQuote2(
        address lbcAddress,
        bool mainnet
    ) internal view returns (Quotes.PegInQuote memory) {
        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 1478412310000000,
                penaltyFee: 10000000000000,
                value: 517700700000000000,
                gasFee: 547377600000,
                fedBtcAddress: FED_BTC_ADDRESS,
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26,
                rskRefundAddress: payable(
                    0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26
                ),
                nonce: 6080686644105603000,
                gasLimit: 21000,
                agreementTimestamp: 1755356567,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: mainnet
                    ? BTC_REFUND_ADDRESS_MAINNET
                    : BTC_REFUND_ADDRESS_TESTNET,
                liquidityProviderBtcAddress: mainnet
                    ? LP_BTC_ADDRESS_MAINNET
                    : LP_BTC_ADDRESS_TESTNET,
                data: new bytes(0)
            });
    }

    /// @notice Creates test quote 3 (nonce: 7756734892733337000)
    function createTestQuote3(
        address lbcAddress,
        bool mainnet
    ) internal view returns (Quotes.PegInQuote memory) {
        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 2009314000000000,
                penaltyFee: 10000000000000,
                value: 578580000000000000,
                gasFee: 547377600000,
                fedBtcAddress: FED_BTC_ADDRESS,
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 7756734892733337000,
                gasLimit: 21000,
                agreementTimestamp: 1755682139,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: mainnet
                    ? BTC_REFUND_ADDRESS_MAINNET
                    : BTC_REFUND_ADDRESS_TESTNET,
                liquidityProviderBtcAddress: mainnet
                    ? LP_BTC_ADDRESS_MAINNET
                    : LP_BTC_ADDRESS_TESTNET,
                data: new bytes(0)
            });
    }
}
