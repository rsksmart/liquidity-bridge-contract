// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";

// Contracts
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";

// Libraries
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

// OpenZeppelin
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Config
import {HelperConfig} from "../../script/HelperConfig.s.sol";

/**
 * @title FlyoverTestBase
 * @notice Unified test base for all Flyover contract tests
 * @dev Uses deployment scripts for consistent contract setup
 *
 * ## Usage
 *
 * For CollateralManagement-only tests:
 *   function setUp() public {
 *       deployCollateralManagement();
 *   }
 *
 * For Discovery tests (includes CollateralManagement):
 *   function setUp() public {
 *       deployDiscovery();
 *   }
 *
 * For PegIn tests (includes CollateralManagement + Discovery):
 *   function setUp() public {
 *       deployPegIn();
 *   }
 *
 * For PegOut tests (includes CollateralManagement + Discovery):
 *   function setUp() public {
 *       deployPegOut();
 *   }
 *
 * For full system tests (all contracts):
 *   function setUp() public {
 *       deployFullSystem();
 *   }
 *
 * For tests needing registered providers:
 *   function setUp() public {
 *       deployFullSystem();
 *       setupProviders();
 *   }
 */
abstract contract FlyoverTestBase is Test {
    // ============================================================
    // Contract Instances
    // ============================================================

    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    BridgeMock public bridgeMock;

    // ============================================================
    // Test Accounts
    // ============================================================

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Private keys for signing (needed for signature validation tests)
    uint256 public pegInLpKey;
    uint256 public pegOutLpKey;
    uint256 public fullLpKey;

    // Role accounts
    address public adder;
    address public slasher;

    // ============================================================
    // Test Constants
    // ============================================================

    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD_PEGIN = 2300 * 65164000;
    uint256 constant TEST_DUST_THRESHOLD_PEGOUT = 0.0000001 ether;
    uint256 constant TEST_MIN_PEGIN = 0.5 ether;
    uint256 constant TEST_BTC_BLOCK_TIME = 3600;
    uint256 constant DISCOVERY_INITIAL_DELAY = 5000;

    uint256 constant ONE_RBTC = 1 ether;
    uint256 constant BASE_COLLATERAL = 10 ether;
    address constant ZERO_ADDRESS = address(0);

    // BTC Mock Constants
    bytes32 constant BLOCK_HEADER_HASH = bytes32(uint256(1));
    uint256 constant PARTIAL_MERKLE_TREE = 0;
    bytes32[] internal merkleHashes;

    // ============================================================
    // Deployment Functions - Using Deployment Scripts
    // ============================================================

    /// @notice Deploy only CollateralManagement contract
    function deployCollateralManagement() internal {
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        HelperConfig.FlyoverConfig memory cfg = _getTestConfig();

        // Inline deployment
        address impl = address(new CollateralManagementContract());
        address admin = address(new ProxyAdmin(owner));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        owner,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage
                    )
                )
            )
        );

        collateralManagement = CollateralManagementContract(payable(proxy));
    }

    /// @notice Deploy CollateralManagement + FlyoverDiscovery
    function deployDiscovery() internal {
        deployCollateralManagement();

        HelperConfig.FlyoverConfig memory cfg = _getTestConfig();

        // Inline deployment
        address impl = address(new FlyoverDiscovery());
        address admin = address(new ProxyAdmin(owner));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (owner, cfg.adminDelay, address(collateralManagement))
                )
            )
        );

        discovery = FlyoverDiscovery(proxy);

        // Setup cross-contract roles
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        vm.stopPrank();
    }

    /// @notice Deploy CollateralManagement + Discovery + PegInContract
    function deployPegIn() internal {
        deployDiscovery();

        bridgeMock = new BridgeMock();

        HelperConfig.FlyoverConfig memory cfg = _getTestConfig();

        // Inline deployment - split to avoid stack too deep
        address impl = address(new PegInContract());
        address admin = address(new ProxyAdmin(owner));
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                cfg.minimumPegIn,
                address(collateralManagement),
                cfg.mainnet
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, admin, initData)
        );

        pegInContract = PegInContract(payable(proxy));

        // Grant COLLATERAL_SLASHER role to PegInContract
        vm.prank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegInContract)
        );
    }

    /// @notice Deploy CollateralManagement + Discovery + PegOutContract
    function deployPegOut() internal {
        deployDiscovery();

        bridgeMock = new BridgeMock();

        HelperConfig.FlyoverConfig memory cfg = _getTestConfig();

        // Inline deployment - split to avoid stack too deep
        address impl = address(new PegOutContract());
        address admin = address(new ProxyAdmin(owner));
        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                address(collateralManagement),
                cfg.mainnet,
                cfg.btcBlockTime
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, admin, initData)
        );

        pegOutContract = PegOutContract(payable(proxy));

        // Grant COLLATERAL_SLASHER role to PegOutContract
        vm.prank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegOutContract)
        );

        // Initialize BTC mocks
        initBtcMocks();
    }

    /// @notice Deploy full system with inline deployment
    function deployFullSystem() internal {
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        bridgeMock = new BridgeMock();

        HelperConfig.FlyoverConfig memory cfg = _getTestConfig();

        // Single ProxyAdmin for all contracts
        address proxyAdmin = address(new ProxyAdmin(owner));

        // 1) CollateralManagement
        address cmImpl = address(new CollateralManagementContract());
        address cmProxy = address(
            new TransparentUpgradeableProxy(
                cmImpl,
                proxyAdmin,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        owner,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage
                    )
                )
            )
        );
        collateralManagement = CollateralManagementContract(payable(cmProxy));

        // 2) FlyoverDiscovery
        address fdImpl = address(new FlyoverDiscovery());
        address fdProxy = address(
            new TransparentUpgradeableProxy(
                fdImpl,
                proxyAdmin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (owner, cfg.adminDelay, cmProxy)
                )
            )
        );
        discovery = FlyoverDiscovery(fdProxy);

        // 3) PegInContract
        {
            address piImpl = address(new PegInContract());
            bytes memory piInitData = abi.encodeCall(
                PegInContract.initialize,
                (
                    owner,
                    payable(address(bridgeMock)),
                    cfg.dustThreshold,
                    cfg.minimumPegIn,
                    cmProxy,
                    cfg.mainnet
                )
            );
            address piProxy = address(
                new TransparentUpgradeableProxy(piImpl, proxyAdmin, piInitData)
            );
            pegInContract = PegInContract(payable(piProxy));
        }

        // 4) PegOutContract
        {
            address poImpl = address(new PegOutContract());
            bytes memory poInitData = abi.encodeCall(
                PegOutContract.initialize,
                (
                    owner,
                    payable(address(bridgeMock)),
                    cfg.dustThreshold,
                    cmProxy,
                    cfg.mainnet,
                    cfg.btcBlockTime
                )
            );
            address poProxy = address(
                new TransparentUpgradeableProxy(poImpl, proxyAdmin, poInitData)
            );
            pegOutContract = PegOutContract(payable(poProxy));
        }

        // Setup cross-contract roles
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegInContract)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegOutContract)
        );
        vm.stopPrank();

        // Initialize BTC mocks
        initBtcMocks();
    }

    // ============================================================
    // Provider Setup
    // ============================================================

    /// @notice Setup providers with collateral and registrations
    function setupProviders() internal {
        require(
            address(discovery) != address(0),
            "Discovery not deployed. Call deployDiscovery() or deployFullSystem() first"
        );

        // Create addresses with known private keys for signature testing
        (pegInLp, pegInLpKey) = makeAddrAndKey("pegInLp");
        (pegOutLp, pegOutLpKey) = makeAddrAndKey("pegOutLp");
        (fullLp, fullLpKey) = makeAddrAndKey("fullLp");

        // Fund providers
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Register providers via Discovery
        vm.prank(pegInLp);
        discovery.register{value: TEST_MIN_COLLATERAL}(
            "Pegin Provider",
            "lp1.com",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(pegOutLp);
        discovery.register{value: TEST_MIN_COLLATERAL}(
            "PegOut Provider",
            "lp2.com",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.prank(fullLp);
        discovery.register{value: TEST_MIN_COLLATERAL * 2}(
            "Full Provider",
            "lp3.com",
            true,
            Flyover.ProviderType.Both
        );
    }

    /// @notice Setup role accounts for CollateralManagement tests
    function setupRoles() internal {
        require(
            address(collateralManagement) != address(0),
            "CollateralManagement not deployed"
        );

        adder = makeAddr("adder");
        slasher = makeAddr("slasher");

        vm.deal(adder, 1000 ether);
        vm.deal(slasher, 100 ether);

        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            adder
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            slasher
        );
        vm.stopPrank();
    }

    /// @notice Setup providers with direct collateral (for CollateralManagement tests)
    function setupProvidersWithCollateral() internal {
        require(
            address(adder) != address(0),
            "Roles not setup. Call setupRoles() first"
        );

        pegInLp = makeAddr("pegInLp");
        pegOutLp = makeAddr("pegOutLp");
        fullLp = makeAddr("fullLp");

        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(
            pegInLp
        );
        collateralManagement.addPegOutCollateralTo{value: BASE_COLLATERAL}(
            pegOutLp
        );
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(
            fullLp
        );
        collateralManagement.addPegOutCollateralTo{value: BASE_COLLATERAL}(
            fullLp
        );
        vm.stopPrank();
    }

    // ============================================================
    // Quote Helpers
    // ============================================================

    /// @notice Create an empty PegIn quote for testing
    function getEmptyPegInQuote()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testAddress = new bytes(20);

        return
            Quotes.PegInQuote({
                callFee: 0,
                penaltyFee: 0,
                value: 0,
                gasFee: 0,
                fedBtcAddress: bytes20(testAddress),
                lbcAddress: ZERO_ADDRESS,
                liquidityProviderRskAddress: ZERO_ADDRESS,
                contractAddress: ZERO_ADDRESS,
                rskRefundAddress: payable(ZERO_ADDRESS),
                nonce: 0,
                gasLimit: 0,
                agreementTimestamp: 0,
                timeForDeposit: 0,
                callTime: 0,
                depositConfirmations: 0,
                callOnRegister: false,
                btcRefundAddress: testAddress,
                liquidityProviderBtcAddress: testAddress,
                data: emptyBytes
            });
    }

    /// @notice Create an empty PegOut quote for testing
    function getEmptyPegOutQuote()
        internal
        pure
        returns (Quotes.PegOutQuote memory)
    {
        bytes memory testAddress = new bytes(20);

        return
            Quotes.PegOutQuote({
                callFee: 0,
                penaltyFee: 0,
                value: 0,
                gasFee: 0,
                lbcAddress: ZERO_ADDRESS,
                lpRskAddress: ZERO_ADDRESS,
                rskRefundAddress: ZERO_ADDRESS,
                nonce: 0,
                agreementTimestamp: 0,
                depositDateLimit: 0,
                transferTime: 0,
                expireDate: 0,
                expireBlock: 0,
                depositConfirmations: 0,
                transferConfirmations: 0,
                depositAddress: testAddress,
                btcRefundAddress: testAddress,
                lpBtcAddress: testAddress
            });
    }

    /// @notice Create a test PegIn quote with populated values
    function createTestPegInQuote(
        address lbcAddress,
        address lpAddress,
        address userAddress
    ) internal view returns (Quotes.PegInQuote memory) {
        bytes
            memory testBtcAddress = hex"6f0000000000000000000000000000000000000000";

        return
            Quotes.PegInQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 0.5 ether,
                gasFee: 100,
                fedBtcAddress: bytes20(
                    hex"0000000000000000000000000000000000000000"
                ),
                lbcAddress: lbcAddress,
                liquidityProviderRskAddress: lpAddress,
                contractAddress: userAddress,
                rskRefundAddress: payable(userAddress),
                nonce: int64(uint64(block.timestamp)),
                gasLimit: 21000,
                agreementTimestamp: uint32(block.timestamp),
                timeForDeposit: 3600,
                callTime: 7200,
                depositConfirmations: 10,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: hex""
            });
    }

    /// @notice Create a test PegOut quote with populated values
    function createTestPegOutQuote(
        address lbcAddress,
        address lpAddress,
        address userAddress
    ) internal view returns (Quotes.PegOutQuote memory) {
        bytes
            memory testBtcAddress = hex"76a914000000000000000000000000000000000000000088ac";

        return
            Quotes.PegOutQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 0.5 ether,
                gasFee: 100,
                lbcAddress: lbcAddress,
                lpRskAddress: lpAddress,
                rskRefundAddress: userAddress,
                nonce: int64(uint64(block.timestamp)),
                agreementTimestamp: uint32(block.timestamp),
                depositDateLimit: uint32(block.timestamp + 600),
                transferTime: 3600,
                expireDate: uint32(block.timestamp + 1000),
                expireBlock: uint32(block.number + 10),
                depositConfirmations: 10,
                transferConfirmations: 2,
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }

    // ============================================================
    // BTC Mock Helpers
    // ============================================================

    /// @notice Initialize BTC mock data
    function initBtcMocks() internal {
        merkleHashes = new bytes32[](1);
        merkleHashes[0] = bytes32(uint256(1));
    }

    /// @notice Creates a BTC block header with a specific timestamp
    function createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);

        // Place timestamp at offset 68 (little-endian)
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));

        return header;
    }

    /// @notice Converts uint64 to 8-byte little-endian
    function toLittleEndian64(
        uint64 value
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(8);
        result[0] = bytes1(uint8(value));
        result[1] = bytes1(uint8(value >> 8));
        result[2] = bytes1(uint8(value >> 16));
        result[3] = bytes1(uint8(value >> 24));
        result[4] = bytes1(uint8(value >> 32));
        result[5] = bytes1(uint8(value >> 40));
        result[6] = bytes1(uint8(value >> 48));
        result[7] = bytes1(uint8(value >> 56));
        return result;
    }

    /// @notice Generates a simple mock BTC transaction for testing
    function generateMockBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal pure returns (bytes memory) {
        // Convert quote value from WEI to SAT (divide by 10^10)
        uint64 satAmount = uint64(quote.value / 1e10);

        // Extract P2PKH hash160 from 21-byte address (skip version byte)
        bytes memory hash160 = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        // Create P2PKH output script
        bytes memory outputScript = abi.encodePacked(
            hex"76a914", // OP_DUP OP_HASH160 PUSH20
            hash160,
            hex"88ac" // OP_EQUALVERIFY OP_CHECKSIG
        );

        // Build mock transaction
        return
            abi.encodePacked(
                hex"01000000", // Version
                hex"01", // 1 input
                hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"00000000",
                hex"6a",
                hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff",
                hex"02", // 2 outputs
                toLittleEndian64(satAmount),
                uint8(outputScript.length),
                outputScript,
                hex"0000000000000000",
                hex"22",
                hex"6a20",
                quoteHash,
                hex"00000000"
            );
    }

    /// @notice Sign a quote hash with a provider's private key
    function signQuoteHash(
        bytes32 quoteHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ============================================================
    // Internal Helpers
    // ============================================================

    /// @notice Get test configuration (uses local/test values)
    function _getTestConfig()
        internal
        returns (HelperConfig.FlyoverConfig memory)
    {
        // Deploy bridge mock if not already deployed
        if (address(bridgeMock) == address(0)) {
            bridgeMock = new BridgeMock();
        }

        return
            HelperConfig.FlyoverConfig({
                bridge: address(bridgeMock),
                minimumCollateral: TEST_MIN_COLLATERAL,
                minimumPegIn: TEST_MIN_PEGIN,
                rewardPercentage: TEST_REWARD_PERCENTAGE,
                resignDelayBlocks: TEST_RESIGN_DELAY_BLOCKS,
                dustThreshold: TEST_DUST_THRESHOLD_PEGIN,
                btcBlockTime: TEST_BTC_BLOCK_TIME,
                mainnet: false,
                adminDelay: TEST_DEFAULT_ADMIN_DELAY
            });
    }
}
