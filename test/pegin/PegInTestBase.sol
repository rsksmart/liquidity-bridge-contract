// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title Base contract for PegIn tests
/// @notice Provides shared deployment and setup logic for PegIn tests
abstract contract PegInTestBase is Test {
    PauseRegistry public pauseRegistry;
    PegInContract public pegInContract;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    BridgeMock public bridgeMock;

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Private keys for signing (needed for signature validation tests)
    uint256 public pegInLpKey;
    uint256 public pegOutLpKey;
    uint256 public fullLpKey;

    // Test constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD = 2300 * 65164000; // From PEGIN_CONSTANTS
    uint256 constant TEST_MIN_PEGIN = 0.5 ether;
    uint256 constant DISCOVERY_INITIAL_DELAY = 5000;
    uint256 constant MIN_COLLATERAL = 0.6 ether;

    address constant ZERO_ADDRESS = address(0);

    /// @notice Deploy PegInContract with all dependencies
    function deployPegInContract() internal {
        // Create owner
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        // Deploy CollateralManagement
        deployCollateralManagement();

        // Deploy Discovery
        deployDiscovery();

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

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
                false, // mainnet
                pauseRegistry
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        pegInContract = PegInContract(payable(address(proxy)));

        // Grant COLLATERAL_SLASHER role to PegInContract
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(owner);
        collateralManagement.grantRole(slasherRole, address(pegInContract));
    }

    function deployCollateralManagement() internal {
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        CollateralManagementContract cmImplementation = new CollateralManagementContract();

        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE,
                pauseRegistry
            )
        );

        ERC1967Proxy cmProxy = new ERC1967Proxy(
            address(cmImplementation),
            cmInitData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(cmProxy))
        );

        require(
            collateralManagement.hasRole(
                collateralManagement.DEFAULT_ADMIN_ROLE(),
                owner
            ),
            "Owner should have DEFAULT_ADMIN_ROLE"
        );
    }

    function deployDiscovery() internal {
        FlyoverDiscovery discoveryImplementation = new FlyoverDiscovery();

        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                owner,
                uint48(DISCOVERY_INITIAL_DELAY),
                address(collateralManagement),
                pauseRegistry
            )
        );

        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImplementation),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        vm.prank(owner);
        collateralManagement.grantRole(adderRole, address(discovery));
    }

    /// @notice Setup providers with collateral
    function setupProviders() internal {
        (pegInLp, pegInLpKey) = makeAddrAndKey("pegInLp");
        (pegOutLp, pegOutLpKey) = makeAddrAndKey("pegOutLp");
        (fullLp, fullLpKey) = makeAddrAndKey("fullLp");

        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        vm.prank(pegInLp, pegInLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pegin Provider",
            "lp1.com",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(pegOutLp, pegOutLp);
        discovery.register{value: MIN_COLLATERAL}(
            "PegOut Provider",
            "lp2.com",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.prank(fullLp, fullLp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "Full Provider",
            "lp3.com",
            true,
            Flyover.ProviderType.Both
        );
    }

    /// @notice Shared helper for constructing a standard PegIn quote fixture
    function _buildPegInQuoteFixture(
        uint256 value,
        address lp,
        address payable refundAddress,
        address destinationContract,
        uint256 nonce
    ) internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: value,
                gasFee: 100,
                fedBtcAddress: bytes20(testBtcAddress),
                lbcAddress: address(pegInContract),
                liquidityProviderRskAddress: lp,
                contractAddress: destinationContract,
                rskRefundAddress: refundAddress,
                nonce: int64(uint64(nonce)),
                gasLimit: 21000,
                agreementTimestamp: uint32(block.timestamp),
                timeForDeposit: 3600,
                callTime: 7200,
                depositConfirmations: 10,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }

    /// @notice Shared helper for signing PegIn quotes
    function _signPegInQuoteWithKey(
        uint256 privateKey,
        Quotes.PegInQuote memory quote
    ) internal view returns (bytes memory) {
        bytes32 eip712Hash = pegInContract.hashPegInQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Shared helper for creating BTC block headers with LE timestamp
    function _btcHeaderFromTimestamp(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));
        return header;
    }

    /// @notice Seeds one non-LP internal balance by forcing refund transfer failure on registerPegIn
    function _seedNonLpRefundLiabilityFixture(
        address lp,
        uint256 lpPrivateKey,
        uint256 value,
        uint256 height,
        bytes memory rawTx,
        bytes memory pmt
    ) internal returns (address creditor, uint256 creditedAmount) {
        WalletMock refundWallet = new WalletMock();
        refundWallet.setRejectFunds(true);
        creditor = address(refundWallet);

        Quotes.PegInQuote memory quote = _buildPegInQuoteFixture(
            value,
            lp,
            payable(creditor),
            address(0xBEEF),
            uint256(uint64(block.timestamp))
        );
        bytes32 quoteHash = pegInContract.hashPegInQuote(quote);
        bytes memory signature = _signPegInQuoteWithKey(lpPrivateKey, quote);
        uint256 peginAmount = quote.value + quote.callFee + quote.gasFee;

        vm.deal(address(this), peginAmount);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(
            height,
            _btcHeaderFromTimestamp(uint32(block.timestamp) + 300)
        );
        bridgeMock.setHeader(
            height + uint256(quote.depositConfirmations) - 1,
            _btcHeaderFromTimestamp(uint32(block.timestamp) + 600)
        );

        vm.prank(lp);
        pegInContract.registerPegIn(quote, signature, rawTx, pmt, height);

        creditedAmount = pegInContract.getBalance(creditor);
        assertGt(
            creditedAmount,
            0,
            "Expected non-LP refund creditor balance to be seeded"
        );
    }
}
