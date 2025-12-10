// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {QuotesV2} from "../../src/legacy/QuotesV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {Mock} from "../../src/test-contracts/Mock.sol";
import {WalletMock} from "../../src/test-contracts/WalletMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PegInTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LiquidityBridgeContractV2 public lbcImpl;
    ERC1967Proxy public lbcProxy;
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

    struct LiquidityProviderInfo {
        address signer;
        uint256 privateKey;
        string name;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    LiquidityProviderInfo[] public liquidityProviders;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    address constant ZERO_ADDRESS = address(0);
    bytes constant ANY_HEX =
        hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    uint256 constant ANY_NUMBER = 10;

    // FFI Helper script paths
    string constant HELPER_SCRIPT_GET_BTC_ADDRESS_BYTES =
        "script/helpers/get-btc-address-bytes.ts";
    string constant HELPER_SCRIPT_PARSE_BTC_ADDRESS =
        "script/helpers/parse-btc-address.ts";
    string constant HELPER_SCRIPT_DECODE_BTC_ADDRESS_BS58 =
        "script/helpers/decode-btc-address-bs58.ts";
    string constant HELPER_SCRIPT_GET_P2SH_ADDRESS_FROM_SCRIPT =
        "script/helpers/get-p2sh-address-from-script.ts";

    // BTC address constants
    bytes constant DECODED_TEST_FED_ADDRESS =
        hex"c39bc4b53918d6058134363d6e57e11a22f9e8fb";
    bytes constant DECODED_P2PKH_ZERO_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";
    bytes constant DECODED_TEST_P2PKH_ADDRESS =
        hex"6f89abcdefabbaabbaabbaabbaabbaabbaabbaabba";

    function setUp() public {
        lbcOwner = address(this);

        // Create 16 test accounts
        for (uint i = 1; i <= 16; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            vm.deal(account, 100 ether);
            accounts.push(account);
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy V1 first, then upgrade to V2 (matching the actual deployment)
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();
        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(address(bridgeMock)),
            0.03 ether, // minCollateral
            0.5 ether, // minPegIn
            uint32(50), // rewardPercentage
            uint32(60), // resignDelayBlocks
            uint256(2300 * 65164000), // dustThreshold
            uint256(1), // btcBlockTime
            false // mainnet
        );
        lbcProxy = new ERC1967Proxy(address(lbcV1Impl), v1InitData);

        // Upgrade to V2
        lbcImpl = new LiquidityBridgeContractV2();
        bytes32 implementationSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        vm.store(
            address(lbcProxy),
            implementationSlot,
            bytes32(uint256(uint160(address(lbcImpl))))
        );

        // Cast to V2 (no need to call initializeV2 since V1 already initialized Ownable/ReentrancyGuard)
        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Create LPs with deterministic private keys
        uint256 lp1Key = uint256(keccak256("lp1_private_key"));
        uint256 lp2Key = uint256(keccak256("lp2_private_key"));
        uint256 lp3Key = uint256(keccak256("lp3_private_key"));

        address lp1 = vm.addr(lp1Key);
        address lp2 = vm.addr(lp2Key);
        address lp3 = vm.addr(lp3Key);

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        // Register 3 liquidity providers
        vm.prank(lp1, lp1);
        lbc.register{value: LP_COLLATERAL}(
            "First LP",
            "http://localhost/api1",
            true,
            "both"
        );

        vm.prank(lp2, lp2);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Second LP",
            "http://localhost/api2",
            true,
            "pegin"
        );

        vm.prank(lp3, lp3);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Third LP",
            "http://localhost/api3",
            true,
            "pegout"
        );

        liquidityProviders.push(
            LiquidityProviderInfo(
                lp1,
                lp1Key,
                "First LP",
                "http://localhost/api1",
                true,
                "both"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp2,
                lp2Key,
                "Second LP",
                "http://localhost/api2",
                true,
                "pegin"
            )
        );
        liquidityProviders.push(
            LiquidityProviderInfo(
                lp3,
                lp3Key,
                "Third LP",
                "http://localhost/api3",
                true,
                "pegout"
            )
        );
    }

    // ============ Helper Functions ============

    struct SignResult {
        bytes32 quoteHash;
        bytes signature;
    }

    struct BalanceSnapshot {
        uint256 lpBalance;
        uint256 lpCollateral;
        uint256 lbcEthBalance;
        uint256 userBalance;
        uint256 refundBalance;
    }

    function getTestPeginQuote(
        address lbcAddress,
        address liquidityProvider,
        uint256 value,
        address destinationAddress,
        address refundAddress,
        bytes memory data
    ) internal view returns (QuotesV2.PeginQuote memory quote) {
        int64 nonce = int64(
            uint64(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            uint256(0x1234567890abcdef)
                        )
                    )
                ) >> 192
            )
        );

        quote = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(DECODED_TEST_FED_ADDRESS),
            lbcAddress: lbcAddress,
            liquidityProviderRskAddress: liquidityProvider,
            btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
            rskRefundAddress: payable(refundAddress),
            liquidityProviderBtcAddress: DECODED_TEST_P2PKH_ADDRESS,
            callFee: 100000000000000,
            penaltyFee: 10000000000000,
            contractAddress: destinationAddress,
            data: data,
            gasLimit: 21000,
            nonce: nonce,
            value: value,
            agreementTimestamp: uint32(block.timestamp),
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            productFeeAmount: 0,
            gasFee: 100
        });
    }

    function signQuote(
        bytes32 quoteHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function captureBalances(
        address lpAddr,
        address userAddr,
        address refundAddr
    ) internal view returns (BalanceSnapshot memory) {
        return
            BalanceSnapshot({
                lpBalance: lbc.getBalance(lpAddr),
                lpCollateral: lbc.getCollateral(lpAddr),
                lbcEthBalance: address(lbc).balance,
                userBalance: userAddr.balance,
                refundBalance: refundAddr.balance
            });
    }

    function totalValue(
        QuotesV2.PeginQuote memory quote
    ) internal pure returns (uint256) {
        return
            quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;
    }

    function getBtcPaymentBlockHeaders(
        QuotesV2.PeginQuote memory quote,
        uint256 firstConfirmationSeconds,
        uint256 nConfirmationSeconds
    )
        internal
        pure
        returns (
            bytes memory firstConfirmationHeader,
            bytes memory nConfirmationHeader
        )
    {
        uint256 firstConfirmationTime = quote.agreementTimestamp +
            firstConfirmationSeconds;
        uint256 nConfirmationTime = quote.agreementTimestamp +
            nConfirmationSeconds;

        // Convert timestamps to little-endian 4-byte hex
        bytes memory firstTimeLE = abi.encodePacked(
            uint8(firstConfirmationTime),
            uint8(firstConfirmationTime >> 8),
            uint8(firstConfirmationTime >> 16),
            uint8(firstConfirmationTime >> 24)
        );

        bytes memory nTimeLE = abi.encodePacked(
            uint8(nConfirmationTime),
            uint8(nConfirmationTime >> 8),
            uint8(nConfirmationTime >> 16),
            uint8(nConfirmationTime >> 24)
        );

        // BTC header: version(4) + prevHash(32) + merkleRoot(32) + timestamp(4) + bits(4) + nonce(4) = 80 bytes
        firstConfirmationHeader = abi.encodePacked(
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"00000000",
            firstTimeLE,
            hex"0000000000000000"
        );

        nConfirmationHeader = abi.encodePacked(
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            hex"00000000",
            nTimeLE,
            hex"0000000000000000"
        );
    }

    function getTestMerkleProof()
        internal
        pure
        returns (
            bytes memory blockHeaderHash,
            bytes memory partialMerkleTree,
            bytes32[] memory merkleBranchHashes
        )
    {
        blockHeaderHash = hex"02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
        partialMerkleTree = hex"02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
        merkleBranchHashes = new bytes32[](1);
        merkleBranchHashes[
            0
        ] = 0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326;
    }

    // ============ Tests ============

    function test_CallContractForUser() public {
        Mock mockContract = new Mock();
        mockContract.set(0);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            20 ether,
            address(mockContract),
            accounts[0],
            abi.encodeWithSelector(Mock.set.selector, int(12))
        );

        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            address(mockContract),
            accounts[0]
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        vm.expectEmit(true, true, false, false);
        emit LiquidityBridgeContractV2.CallForUser(
            liquidityProviders[0].signer,
            address(mockContract),
            quote.gasLimit,
            quote.value,
            quote.data,
            true,
            quoteHash
        );
        lbc.callForUser{value: quote.value}(quote);

        assertEq(
            lbc.getBalance(liquidityProviders[0].signer),
            before.lpBalance
        );

        vm.prank(liquidityProviders[0].signer);
        vm.expectEmit(true, false, false, false);
        emit LiquidityBridgeContractV2.PegInRegistered(
            quoteHash,
            int256(totalValue(quote))
        );
        int256 result = lbc.registerPegIn(quote, sig, hex"1010", hex"0202", 10);

        assertEq(result, int256(totalValue(quote)));
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            totalValue(quote)
        );
        assertEq(
            address(lbc).balance - before.lbcEthBalance,
            totalValue(quote)
        );
        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral
        );
        assertEq(mockContract.check(), 12);
    }

    function test_FailOnContractCallDueToInvalidLbcAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[0];
        address refundAddress = accounts[1];
        address notLbcAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            notLbcAddress,
            provider.signer,
            0.5 ether,
            destinationAddress,
            refundAddress,
            hex""
        );

        vm.startPrank(provider.signer);

        // Should fail with LBC019 (insufficient balance)
        vm.expectRevert("LBC019");
        lbc.callForUser(quote);

        // Should fail with LBC051 (invalid lbc address)
        vm.expectRevert("LBC051");
        lbc.callForUser{value: quote.value}(quote);

        // registerPegIn should also fail
        vm.expectRevert("LBC051");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_FailOnContractCallDueToInvalidContractAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];

        // Use bridge address as contract address (not allowed)
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            address(bridgeMock),
            accounts[0],
            hex""
        );

        vm.startPrank(provider.signer);

        vm.expectRevert("LBC052");
        lbc.hashQuote(quote);

        vm.expectRevert("LBC052");
        lbc.callForUser{value: quote.value}(quote);

        vm.expectRevert("LBC052");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_FailOnContractCallDueToInvalidUserBtcRefundAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[0];
        address destinationAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        bytes[] memory invalidAddresses = new bytes[](2);
        invalidAddresses[0] = hex"0000000000000000000000000000000000000012"; // 20 bytes
        invalidAddresses[1] = hex"00000000000000000000000000000000000000000012"; // 22 bytes

        for (uint i = 0; i < invalidAddresses.length; i++) {
            quote.btcRefundAddress = invalidAddresses[i];

            vm.startPrank(provider.signer);

            vm.expectRevert("LBC053");
            lbc.hashQuote(quote);

            vm.expectRevert("LBC053");
            lbc.callForUser{value: quote.value}(quote);

            vm.expectRevert("LBC053");
            lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

            vm.stopPrank();
        }
    }

    function test_FailOnContractCallDueToInvalidLpBtcAddress() public {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[0];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.5 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        bytes[] memory invalidAddresses = new bytes[](2);
        invalidAddresses[0] = hex"0000000000000000000000000000000000000012"; // 20 bytes
        invalidAddresses[1] = hex"00000000000000000000000000000000000000000012"; // 22 bytes

        for (uint i = 0; i < invalidAddresses.length; i++) {
            quote.liquidityProviderBtcAddress = invalidAddresses[i];

            vm.startPrank(provider.signer);

            vm.expectRevert("LBC054");
            lbc.hashQuote(quote);

            vm.expectRevert("LBC054");
            lbc.callForUser{value: quote.value}(quote);

            vm.expectRevert("LBC054");
            lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

            vm.stopPrank();
        }
    }

    function test_FailOnContractCallDueToQuoteValuePlusFeeBelowMinPegIn()
        public
    {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[2];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            0.1 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        vm.startPrank(provider.signer);

        vm.expectRevert("LBC055");
        lbc.hashQuote(quote);

        vm.expectRevert("LBC055");
        lbc.callForUser{value: quote.value}(quote);

        vm.expectRevert("LBC055");
        lbc.registerPegIn(quote, ANY_HEX, ANY_HEX, ANY_HEX, ANY_NUMBER);

        vm.stopPrank();
    }

    function test_ShouldTransferValueForUser() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[1].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.productFeeAmount = 100000000000;

        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[1].signer,
            accounts[1],
            accounts[2]
        );
        uint256 feeBalanceBefore = ZERO_ADDRESS.balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[1].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[1].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(
            lbc.getBalance(liquidityProviders[1].signer),
            before.lpBalance
        );

        vm.prank(liquidityProviders[1].signer);
        lbc.registerPegIn(quote, sig, ANY_HEX, ANY_HEX, 10);

        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(
            address(lbc).balance - before.lbcEthBalance,
            totalValue(quote) - quote.productFeeAmount
        );
        assertEq(
            lbc.getBalance(liquidityProviders[1].signer) - before.lpBalance,
            totalValue(quote) - quote.productFeeAmount
        );
        assertEq(
            ZERO_ADDRESS.balance - feeBalanceBefore,
            quote.productFeeAmount
        );
        assertEq(
            lbc.getCollateral(liquidityProviders[1].signer),
            before.lpCollateral
        );
    }

    function test_NotGenerateTransactionToDAOWhenProductFeeIsZeroInRegisterPegIn()
        public
    {
        LiquidityProviderInfo memory provider = liquidityProviders[1];
        address destinationAddress = accounts[1];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            provider.signer,
            10 ether,
            destinationAddress,
            destinationAddress,
            hex""
        );

        uint256 peginAmount = totalValue(quote);

        // Hash and sign
        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            provider.privateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Setup bridge
        (
            bytes memory firstHeader,
            bytes memory nHeader
        ) = getBtcPaymentBlockHeaders(quote, 300, 600);
        uint256 height = 10;
        uint256 feeCollectorBalanceBefore = ZERO_ADDRESS.balance;

        bridgeMock.setPegin{value: peginAmount}(quoteHash);
        bridgeMock.setHeader(height, firstHeader);
        bridgeMock.setHeader(height + quote.depositConfirmations - 1, nHeader);

        // Call for user
        vm.prank(provider.signer);
        lbc.callForUser{value: quote.value}(quote);

        // Register pegin
        vm.recordLogs();
        vm.prank(provider.signer);
        lbc.registerPegIn(quote, signature, ANY_HEX, ANY_HEX, height);

        // Verify no DaoFeeSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundDaoFeeSent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DaoFeeSent(bytes32,uint256)")) {
                foundDaoFeeSent = true;
                break;
            }
        }
        assertFalse(foundDaoFeeSent, "Should not emit DaoFeeSent");

        // Verify productFeeAmount is 0
        assertEq(quote.productFeeAmount, 0);

        // Verify fee collector balance unchanged
        assertEq(ZERO_ADDRESS.balance, feeCollectorBalanceBefore);
    }

    function test_ThrowErrorInHashQuoteIfSummingQuoteAgreementTimestampAndTimeForDepositCauseOverflow()
        public
    {
        address user = accounts[0];

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            user,
            user,
            hex""
        );

        quote.agreementTimestamp = 4294967294;
        quote.timeForDeposit = 4294967294;

        vm.expectRevert("LBC071");
        lbc.hashQuote(quote);
    }

    function test_TransferValueAndRefundRemaining() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[1].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 additionalFunds = 1000000000000;
        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[1].signer,
            accounts[1],
            accounts[2]
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[1].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote) + additionalFunds}(
            quoteHash
        );
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[1].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(
            lbc.getBalance(liquidityProviders[1].signer),
            before.lpBalance
        );

        vm.prank(liquidityProviders[1].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(totalValue(quote) + additionalFunds));
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(
            address(lbc).balance - before.lbcEthBalance,
            totalValue(quote)
        );
        assertEq(
            lbc.getBalance(liquidityProviders[1].signer) - before.lpBalance,
            totalValue(quote)
        );
        assertEq(accounts[2].balance - before.refundBalance, additionalFunds);
        assertEq(
            lbc.getCollateral(liquidityProviders[1].signer),
            before.lpCollateral
        );
    }

    function test_RefundRemainingAmountToLPInCaseRefundingToQuoteRskRefundAddressFails()
        public
    {
        WalletMock walletMock = new WalletMock();
        walletMock.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(walletMock),
            hex""
        );

        uint256 additionalFunds = 1000000000000;
        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            accounts[1],
            address(walletMock)
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote) + additionalFunds}(
            quoteHash
        );
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer),
            before.lpBalance
        );

        vm.prank(liquidityProviders[0].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(totalValue(quote) + additionalFunds));
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(
            address(lbc).balance - before.lbcEthBalance,
            totalValue(quote) + additionalFunds
        );
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            totalValue(quote) + additionalFunds
        );
        assertEq(address(walletMock).balance, before.refundBalance);
        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral
        );
    }

    function test_RefundUserOnFailedCall() public {
        Mock mockContract = new Mock();

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            address(mockContract),
            accounts[2],
            abi.encodeWithSelector(Mock.fail.selector)
        );

        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            address(mockContract),
            accounts[2]
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            quote.value
        );

        uint256 lpBal = lbc.getBalance(liquidityProviders[0].signer);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - lpBal,
            quote.callFee + quote.gasFee
        );
        assertEq(accounts[2].balance - before.refundBalance, quote.value);
        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral
        );
        assertEq(address(mockContract).balance, before.userBalance);
    }

    function test_RefundUserOnMissedCall() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            accounts[1],
            accounts[2]
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(accounts[1].balance, before.userBalance);
        assertEq(
            accounts[2].balance - before.refundBalance,
            quote.value + quote.callFee + quote.gasFee
        );
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            reward
        );
        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral - quote.penaltyFee
        );
        assertEq(address(lbc).balance, before.lbcEthBalance);
    }

    function test_NoOneBeRefundedInRegisterPegInOnMissedCallInCaseRefundingToQuoteRskRefundAddressFails()
        public
    {
        WalletMock walletMock = new WalletMock();
        walletMock.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(walletMock),
            hex""
        );

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        uint256 walletBalBefore = lbc.getBalance(address(walletMock));
        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 lbcEthBefore = address(lbc).balance;
        uint256 callerBalBefore = lbc.getBalance(accounts[2]);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(11, h2);

        vm.prank(accounts[2]);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            lpCollBefore - quote.penaltyFee
        );
        assertEq(address(walletMock).balance, 0);
        assertEq(address(lbc).balance - lbcEthBefore, totalValue(quote));
        assertEq(lbc.getBalance(accounts[2]) - callerBalBefore, reward);
        assertEq(lbc.getBalance(address(walletMock)), walletBalBefore);
    }

    function test_NotPenalizeWithLateDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.timeForDeposit = 1;

        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].topics[0] ==
                    keccak256("Penalized(address,uint256,bytes32)")
            );
        }

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), lpCollBefore);
        assertEq(accounts[2].balance - refundBefore, totalValue(quote));
    }

    function test_NotPenalizeWithInsufficientDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 insufficientDeposit = totalValue(quote) - 1;
        uint256 lpCollBefore = lbc.getCollateral(liquidityProviders[0].signer);
        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: insufficientDeposit}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].topics[0] ==
                    keccak256("Penalized(address,uint256,bytes32)")
            );
        }

        assertEq(lbc.getCollateral(liquidityProviders[0].signer), lpCollBefore);
        assertEq(accounts[2].balance - refundBefore, insufficientDeposit);
    }

    function test_ShouldPenalizeOnLateCall() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callTime = 1;

        uint256 reward = (quote.penaltyFee * lbc.getRewardPercentage()) / 100;
        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            accounts[1],
            accounts[2]
        );

        vm.warp(block.timestamp + 300);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            100,
            200
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral - quote.penaltyFee
        );
        assertEq(accounts[1].balance - before.userBalance, quote.value);
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            reward + totalValue(quote)
        );
    }

    function test_NotUnderflowWhenPenaltyIsHigherThanCollateral() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.penaltyFee = LP_COLLATERAL + 1;
        quote.callTime = 1;

        uint256 reward = ((LP_COLLATERAL / 2) * lbc.getRewardPercentage()) /
            100;
        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            accounts[1],
            accounts[2]
        );

        vm.warp(block.timestamp + 300);

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            100,
            200
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            reward + totalValue(quote)
        );
        assertEq(accounts[1].balance, before.userBalance + quote.value);
        assertEq(lbc.getCollateral(liquidityProviders[0].signer), 0);
    }

    function test_ShouldNotAllowAttackerToStealFunds() public {
        // Attacker controls a liquidity provider and destination address
        LiquidityProviderInfo memory attackingLP = liquidityProviders[0];
        address attackerDestAddress = accounts[9];

        // Good LP adds funds
        vm.prank(liquidityProviders[1].signer);
        lbc.deposit{value: 20 ether}();

        // Create evil quote where attacker is both LP and dest
        QuotesV2.PeginQuote memory quote = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(0),
            btcRefundAddress: hex"000000000000000000000000000000000000000000",
            liquidityProviderBtcAddress: hex"000000000000000000000000000000000000000000",
            rskRefundAddress: payable(attackerDestAddress),
            liquidityProviderRskAddress: attackingLP.signer, // Use attacking LP address
            data: hex"",
            gasLimit: 30000,
            callFee: 1,
            nonce: 1,
            lbcAddress: address(lbc),
            agreementTimestamp: 1661788988,
            timeForDeposit: 600,
            callTime: 600,
            depositConfirmations: 10,
            penaltyFee: 0,
            callOnRegister: true,
            productFeeAmount: 1,
            gasFee: 1,
            value: 10 ether,
            contractAddress: attackerDestAddress
        });

        uint256 transferredInBTC = 100; // Only 100 wei transferred

        // Hash and sign
        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes32 ethSignedMessageHash = quoteHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            attackingLP.privateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Setup bridge
        (
            bytes memory firstHeader,
            bytes memory nHeader
        ) = getBtcPaymentBlockHeaders(quote, 300, 600);
        uint256 height = 10;

        bridgeMock.setHeader(height, firstHeader);
        bridgeMock.setHeader(height + quote.depositConfirmations - 1, nHeader);
        bridgeMock.setPegin{value: transferredInBTC}(quoteHash);

        // Try to exploit
        vm.prank(attackingLP.signer);
        vm.expectRevert("LBC057");
        lbc.registerPegIn(quote, signature, hex"0101", hex"0202", height);
    }

    function test_PayWithInsufficientDepositThatIsNotLowerThanAgreedAmountMinusDelta()
        public
    {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            0.7 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callFee = 0.00001 ether;
        quote.gasFee = 0.00003 ether;

        uint256 delta = totalValue(quote) / 10000;
        uint256 peginAmount = totalValue(quote) - delta;

        BalanceSnapshot memory before = captureBalances(
            liquidityProviders[0].signer,
            accounts[1],
            accounts[2]
        );

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            100,
            200
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(21, h2);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);

        vm.prank(liquidityProviders[0].signer);
        lbc.callForUser{value: quote.value}(quote);

        vm.prank(liquidityProviders[0].signer);
        int256 result = lbc.registerPegIn(quote, sig, bHash, pmt, 10);

        assertEq(result, int256(peginAmount));
        assertEq(
            lbc.getCollateral(liquidityProviders[0].signer),
            before.lpCollateral
        );
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer) - before.lpBalance,
            peginAmount
        );
        assertEq(address(lbc).balance - before.lbcEthBalance, peginAmount);
        assertEq(accounts[1].balance - before.userBalance, quote.value);
    }

    function test_RevertOnInsufficientDeposit() public {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            0.7 ether,
            accounts[1],
            accounts[2],
            hex""
        );
        quote.callFee = 0.000005 ether;
        quote.gasFee = 0.000006 ether;

        uint256 peginAmount = totalValue(quote) -
            (totalValue(quote) / 10000) -
            1;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            100,
            200
        );
        (bytes memory bHash, bytes memory pmt, ) = getTestMerkleProof();

        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(21, h2);
        bridgeMock.setPegin{value: peginAmount}(quoteHash);

        vm.prank(liquidityProviders[0].signer);
        vm.expectRevert("LBC057");
        lbc.registerPegIn(quote, sig, bHash, pmt, 10);
    }

    function test_ShouldDemonstrateFundsBeingLockedWhenRskRefundAddressRevertsOnRegisterPegInWithoutCallForUser()
        public
    {
        WalletMock maliciousContract = new WalletMock();
        maliciousContract.setRejectFunds(true);

        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            address(maliciousContract),
            hex""
        );

        uint256 lbcBefore = address(lbc).balance;
        uint256 malBalBefore = lbc.getBalance(address(maliciousContract));

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, hex"0101", hex"0202", 10);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundBalInc = false;
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("BalanceIncrease(address,uint256)")
            ) {
                (address dest, uint256 amt) = abi.decode(
                    logs[i].data,
                    (address, uint256)
                );
                if (
                    (dest == address(maliciousContract) ||
                        dest == liquidityProviders[0].signer) &&
                    amt == totalValue(quote)
                ) {
                    foundBalInc = true;
                }
            }
        }
        assertFalse(foundBalInc);

        assertEq(lbc.getBalance(address(maliciousContract)), malBalBefore);
        assertEq(address(lbc).balance - lbcBefore, totalValue(quote));
        assertEq(address(maliciousContract).balance, 0);
    }

    function test_ShouldHandleRefundCorrectlyWhenRskRefundAddressCanReceiveFundsOnRegisterPegInWithoutCallForUser()
        public
    {
        QuotesV2.PeginQuote memory quote = getTestPeginQuote(
            address(lbc),
            liquidityProviders[0].signer,
            10 ether,
            accounts[1],
            accounts[2],
            hex""
        );

        uint256 refundBefore = accounts[2].balance;

        bytes32 quoteHash = lbc.hashQuote(quote);
        bytes memory sig = signQuote(
            quoteHash,
            liquidityProviders[0].privateKey
        );

        (bytes memory h1, bytes memory h2) = getBtcPaymentBlockHeaders(
            quote,
            300,
            600
        );
        bridgeMock.setPegin{value: totalValue(quote)}(quoteHash);
        bridgeMock.setHeader(10, h1);
        bridgeMock.setHeader(19, h2);

        vm.recordLogs();
        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(quote, sig, hex"0101", hex"0202", 10);

        assertEq(accounts[2].balance - refundBefore, totalValue(quote));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("BalanceIncrease(address,uint256)")
            ) {
                (address dest, uint256 amt) = abi.decode(
                    logs[i].data,
                    (address, uint256)
                );
                assertFalse(dest == accounts[2] && amt == totalValue(quote));
            }
        }

        assertEq(lbc.getBalance(accounts[2]), 0);
    }

    // ============ Missing Tests ============

    /// @notice Test verify depositAddress for given quote
    /// @dev  Calculates the expected deposit address dynamically for our quote structure
    function test_VerifyDepositAddressForGivenQuote() public {
        // Test Case 1
        // Note: fedBtcAddress is the decoded address without the version byte (slice(1))
        // "2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p" decoded -> c4896ed9f3446d51b5510f7f0b6ef81b2bde55140e
        // slice(1) removes version byte c4 -> 896ed9f3446d51b5510f7f0b6ef81b2bde55140e
        QuotesV2.PeginQuote memory quote1 = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(
                hex"896ed9f3446d51b5510f7f0b6ef81b2bde55140e"
            ), // 2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p.slice(1)
            lbcAddress: address(lbc),
            liquidityProviderRskAddress: liquidityProviders[0].signer,
            btcRefundAddress: _decodeBtcAddress(
                "mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW"
            ),
            rskRefundAddress: payable(accounts[0]),
            liquidityProviderBtcAddress: _decodeBtcAddress(
                "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
            ),
            callFee: 1000000000000000,
            penaltyFee: 1000000,
            contractAddress: accounts[0],
            data: new bytes(0),
            gasLimit: 46000,
            nonce: 3426962016206607167,
            value: 600000000000000000,
            agreementTimestamp: 1691772110,
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            productFeeAmount: 6000000000000000,
            gasFee: 3000000000000000
        });

        // Calculate the expected deposit address for this quote
        bytes32 quoteHash1 = lbc.hashQuote(quote1);
        bytes32 derivationValue1 = keccak256(
            bytes.concat(
                quoteHash1,
                quote1.btcRefundAddress,
                bytes20(quote1.lbcAddress),
                quote1.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript1 = bytes.concat(
            hex"20",
            derivationValue1,
            hex"75",
            bridgeMock.getActivePowpegRedeemScript()
        );

        // Calculate P2SH address from redeem script using FFI
        bytes memory expectedDepositAddr1 = _getP2SHAddressFromScript(
            flyoverRedeemScript1,
            false
        );
        assertTrue(
            lbc.validatePeginDepositAddress(quote1, expectedDepositAddr1),
            "Deposit address 1 should match"
        );

        // Test Case 2
        QuotesV2.PeginQuote memory quote2 = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(
                hex"896ed9f3446d51b5510f7f0b6ef81b2bde55140e"
            ),
            lbcAddress: address(lbc),
            liquidityProviderRskAddress: liquidityProviders[0].signer,
            btcRefundAddress: _decodeBtcAddress(
                "mi5vEG69RGhi3RKsn7bWco5xnafZvsXvrF"
            ),
            rskRefundAddress: payable(accounts[1]),
            liquidityProviderBtcAddress: _decodeBtcAddress(
                "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
            ),
            callFee: 1000000000000000,
            penaltyFee: 1000000,
            contractAddress: accounts[1],
            data: new bytes(0),
            gasLimit: 46000,
            nonce: 7363369648470809209,
            value: 700000000000000000,
            agreementTimestamp: 1691873604,
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            productFeeAmount: 7000000000000000,
            gasFee: 4000000000000000
        });

        bytes32 quoteHash2 = lbc.hashQuote(quote2);
        bytes32 derivationValue2 = keccak256(
            bytes.concat(
                quoteHash2,
                quote2.btcRefundAddress,
                bytes20(quote2.lbcAddress),
                quote2.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript2 = bytes.concat(
            hex"20",
            derivationValue2,
            hex"75",
            bridgeMock.getActivePowpegRedeemScript()
        );
        bytes memory expectedDepositAddr2 = _getP2SHAddressFromScript(
            flyoverRedeemScript2,
            false
        );
        assertTrue(
            lbc.validatePeginDepositAddress(quote2, expectedDepositAddr2),
            "Deposit address 2 should match"
        );

        // Test Case 3
        QuotesV2.PeginQuote memory quote3 = QuotesV2.PeginQuote({
            fedBtcAddress: bytes20(
                hex"896ed9f3446d51b5510f7f0b6ef81b2bde55140e"
            ),
            lbcAddress: address(lbc),
            liquidityProviderRskAddress: liquidityProviders[0].signer,
            btcRefundAddress: _decodeBtcAddress(
                "mjSE41mAMwqdYsXiibUgyWe4oESoCygf96"
            ),
            rskRefundAddress: payable(accounts[2]),
            liquidityProviderBtcAddress: _decodeBtcAddress(
                "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
            ),
            callFee: 1000000000000000,
            penaltyFee: 1000000,
            contractAddress: accounts[2],
            data: new bytes(0),
            gasLimit: 46000,
            nonce: 8681289575209299775,
            value: 800000000000000000,
            agreementTimestamp: 1691874253,
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 10,
            callOnRegister: false,
            productFeeAmount: 8000000000000000,
            gasFee: 5000000000000000
        });

        bytes32 quoteHash3 = lbc.hashQuote(quote3);
        bytes32 derivationValue3 = keccak256(
            bytes.concat(
                quoteHash3,
                quote3.btcRefundAddress,
                bytes20(quote3.lbcAddress),
                quote3.liquidityProviderBtcAddress
            )
        );
        bytes memory flyoverRedeemScript3 = bytes.concat(
            hex"20",
            derivationValue3,
            hex"75",
            bridgeMock.getActivePowpegRedeemScript()
        );
        bytes memory expectedDepositAddr3 = _getP2SHAddressFromScript(
            flyoverRedeemScript3,
            false
        );
        assertTrue(
            lbc.validatePeginDepositAddress(quote3, expectedDepositAddr3),
            "Deposit address 3 should match"
        );
    }

    /// @notice Test refund pegin with wrong amount without penalizing the LP (real cases)
    /// @dev Uses real mainnet transaction data to ensure compatibility with actual edge cases
    function test_RefundPegInWithWrongAmountWithoutPenalizingLP() public {
        // Decode BTC addresses from base58check format
        // "3LxPz39femVBL278mTiBvgzBNMVFqXssoH" (P2SH mainnet) -> slice(1) removes version byte
        bytes20 fedBtcAddr = bytes20(
            hex"a157fd1a536371656f3c19c2005199308a49bc9c"
        );
        // "17kksixYkbHeLy9okV16kr4eAxVhFkRhP" (P2PKH mainnet) -> full decoded bytes
        bytes
            memory lpBtcAddr = hex"00840098213fec4001cdc4a77cc3340f5bb83d9ed5";
        // "1K5X7aTGfZGksihgNdDschakaxp8ZhT1F3" (P2PKH mainnet) -> full decoded bytes
        bytes
            memory userBtcAddr1 = hex"009b51cc55c4ddc75b5a8e0c1cfee76e063e4b81d3";

        // Test Case 1: Transaction with slight underpayment
        uint256 regtestMultiplier = 100;

        QuotesV2.PeginQuote memory quote1 = QuotesV2.PeginQuote({
            fedBtcAddress: fedBtcAddr,
            lbcAddress: address(lbc),
            liquidityProviderRskAddress: liquidityProviders[0].signer,
            btcRefundAddress: userBtcAddr1,
            rskRefundAddress: payable(
                0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10
            ),
            liquidityProviderBtcAddress: lpBtcAddr,
            callFee: 100000000000000 * regtestMultiplier,
            penaltyFee: 10000000000000 * regtestMultiplier,
            contractAddress: 0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10,
            data: new bytes(0),
            gasLimit: 21000,
            nonce: int64(uint64(block.timestamp)), // Use unique nonce
            value: 5200000000000000 * regtestMultiplier,
            agreementTimestamp: uint32(block.timestamp),
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 2,
            callOnRegister: false,
            productFeeAmount: 0,
            gasFee: 1354759560000 * regtestMultiplier
        });

        // Real refund amount from mainnet (slightly different from expected), scaled by 100x
        uint256 refundAmount1 = 5301350000000000 * regtestMultiplier;

        // Calculate quote hash
        bytes32 quoteHash1 = lbc.hashQuote(quote1);

        // Setup bridge to return this amount
        vm.deal(address(bridgeMock), refundAmount1);
        bridgeMock.setPegin{value: refundAmount1}(quoteHash1);

        // Setup headers (simplified - real test would use actual BTC headers)
        bytes memory header = _createBtcBlockHeader(
            uint32(block.timestamp) + 300
        );
        bridgeMock.setHeader(862825, header);
        bridgeMock.setHeader(862826, header);

        // Register - should refund without penalizing
        bytes memory signature1 = signQuote(
            quoteHash1,
            liquidityProviders[0].privateKey
        );

        uint256 refundBalanceBefore = quote1.rskRefundAddress.balance;

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(
            quote1,
            signature1,
            hex"020000000212bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff046d8f4e5fa8d6cc5fa23c50640249461b646e8a4722c9cfbfbff00c049d559f0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff02d71608000000000017a9149fa51efd2954990e4974e7b13468fb8be54512d8872d2507000000000017a914b979999438ade0fdd2cf303fca55ea29aec2392b8700000000",
            hex"800c00000d3eb13be27a4110f06ca8e4b4b00103e10ac6ba5f9123934764ac9555e2ec3c7b88a5464adca8b40a548741a8262dc2ab228f89cbd51bbf57f3f5d67130820ae3f9b7625821c2d9718d6611de40edfa1eb42181f180aab3891730584921a125dddba628c1d3f5fca59e0b68494aae191ab14db30b79e07962da298a52bcf077905661f80bd5731e0c80524ba2f7dcad0bd05a0d470bccdb5c5889c9c71ac7c5bca7f6cebd492154af69f2b98bcf7995444c765a18445a5ef212eb5f8ead5a441a45536e4075022614df043d03b2449113a00f32cff333024d3a1d66d84d4a31c012bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea34b89cb98fac941bdd048d4a8f371d7b9f132ad19f1542556c89b4e8701022de51f6d49aa8f7e7d01591de9bdef65351e8590f111ea9be5550f66a3d4a734758e26b8edf2bfe9c4375929fea7b7197a24589648f8e7b934a6caa2d9c7583e64a28db12de953b0abddbdc3edb28b845eaca02f56dd52aa04e3131dc539c0f646f35751d1ec529231acd5cb079b4a2b678ecd3fc07636be878e6336d546518562e04af6a1500",
            862825
        );

        // Verify refund address received the funds
        assertEq(
            quote1.rskRefundAddress.balance,
            refundBalanceBefore + refundAmount1,
            "Refund address should receive the amount"
        );

        // Verify LP was not penalized (balance stays 0 since no callForUser)
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer),
            0,
            "LP should not be penalized for wrong amount"
        );

        // Test Case 2: Another real transaction with different parameters
        // "171gGjg8NeLUonNSrFmgwkgT1jgqzXR6QX" (P2PKH mainnet) -> 0x00 + 20 bytes hash
        bytes
            memory userBtcAddr2 = hex"0013c5b9da8f2f01c8ae8bcf0ff05c1d9c81d73d02";

        QuotesV2.PeginQuote memory quote2 = QuotesV2.PeginQuote({
            fedBtcAddress: fedBtcAddr,
            lbcAddress: address(lbc),
            liquidityProviderRskAddress: liquidityProviders[0].signer,
            btcRefundAddress: userBtcAddr2,
            rskRefundAddress: payable(
                0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82
            ),
            liquidityProviderBtcAddress: lpBtcAddr,
            callFee: 100000000000000 * regtestMultiplier,
            penaltyFee: 10000000000000 * regtestMultiplier,
            contractAddress: 0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82,
            data: new bytes(0),
            gasLimit: 21000,
            nonce: int64(uint64(block.timestamp + 1)), // Use unique nonce
            value: 8000000000000000 * regtestMultiplier,
            agreementTimestamp: uint32(block.timestamp + 1),
            timeForDeposit: 3600,
            callTime: 7200,
            depositConfirmations: 2,
            callOnRegister: false,
            productFeeAmount: 0,
            gasFee: 1341211956000 * regtestMultiplier
        });

        bytes32 quoteHash2 = lbc.hashQuote(quote2);
        uint256 refundAmount2 = 8101340000000000 * regtestMultiplier;

        // Setup bridge
        vm.deal(address(bridgeMock), refundAmount2);
        bridgeMock.setPegin{value: refundAmount2}(quoteHash2);
        bridgeMock.setHeader(862859, header);
        bridgeMock.setHeader(862860, header);

        // Register
        bytes memory signature2 = signQuote(
            quoteHash2,
            liquidityProviders[0].privateKey
        );

        uint256 refundBalance2Before = quote2.rskRefundAddress.balance;

        vm.prank(liquidityProviders[0].signer);
        lbc.registerPegIn(
            quote2,
            signature2,
            hex"010000000148e9e71dafee5a901be4eceb5aca361c083481b70496f4e3da71e5d969add1820000000017160014b88ef07cd7bcc022b6d73c4764ce5db0887d5b05ffffffff02965c0c000000000017a9141b67149e474f0d7757181f4db89257f27a64738387125b01000000000017a914785c3e807e54dc41251d6377da0673123fa87bc88700000000",
            hex"a71100000e7fe369f81a807a962c8e528debd0b46cbfa4f8dfbc02a62674dd41a73f4c4bde0508a9e309e5836703375a58ab116b95434552ca2e460c3273cd2caa13350aefc3c8152a8150f738cd18ff33e69f19b727bff9c2b92aa06e6d0971e9b49893075f2d926bbb9f0884640363b79b6a668a178f140c13f25b48ec975357822ce38c733f6de9b32f6910ff3cd838efd274cd784ab204b74f281ef68146c334f509613d022554f281465dfcd597305c988c4b06e297e5d777afdb66c3391c3c471ebf9a1e051ba38201f08ca758d2dc83a71c34088e6785c1a775e2bde492361462cac9e7042653341cd1e190d0265a33f46ba564dc6116689cf19a8af6816c006df69803008246d44bc849babfbcc3de601fba3d10d696bf4b4d9cb8e291584e7d24bb2c81282972e71cb4493fb4966fcb483d6b62b24a0e25f912ee857d8843e4fa6181b8351f0a300e14503d51f46f367ec872712004535a56f14c65430f044f9685137a1afb2dc0aa402fde8d83b072ef0c4357529466e017dfb2935444103bbeec61bf8944924371921eefd02f35fd5283f3b7bce58a6f4ca15fb32cee8869be8d7720501ec18cc097c236b19212514582212719aede2400b1dd1ff43208ac7504bfb60a00",
            862859
        );

        // Verify refund
        assertEq(
            quote2.rskRefundAddress.balance,
            refundBalance2Before + refundAmount2,
            "Refund address 2 should receive the amount"
        );

        // Verify no penalization
        assertEq(
            lbc.getBalance(liquidityProviders[0].signer),
            0,
            "LP should not be penalized for second transaction"
        );
    }

    // ============ Helper Functions ============

    /// @notice Decodes a BTC address from base58check format using FFI (for quote addresses)
    /// @param addressStr The base58check encoded BTC address
    /// @return The decoded address bytes (version byte + hash160)
    function _decodeBtcAddress(
        string memory addressStr
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_PARSE_BTC_ADDRESS;
        inputs[3] = addressStr;

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    /// @notice Decodes a BTC address using bs58 (no checksum, for deposit addresses)
    /// @param addressStr The base58 encoded BTC address
    /// @return The decoded address bytes (version byte + hash160)
    function _decodeBtcAddressBs58(
        string memory addressStr
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_DECODE_BTC_ADDRESS_BS58;
        inputs[3] = addressStr;

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    /// @notice Creates a simple BTC block header for testing
    /// @param timestamp The timestamp for the header
    /// @return The block header bytes
    function _createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);
        // Version (4 bytes) - set to 0x20000000
        header[0] = 0x20;
        header[1] = 0x00;
        header[2] = 0x00;
        header[3] = 0x00;
        // Previous block hash (32 bytes) - zeros
        // Merkle root (32 bytes) - zeros
        // Timestamp (4 bytes)
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));
        // Bits (4 bytes) - set to 0x1d00ffff
        header[72] = 0x1d;
        header[73] = 0x00;
        header[74] = 0xff;
        header[75] = 0xff;
        // Nonce (4 bytes) - zeros
        return header;
    }

    /// @notice Calculates P2SH address from a redeem script using FFI
    /// @param redeemScript The redeem script bytes
    /// @param isMainnet Whether this is for mainnet (false for testnet)
    /// @return The P2SH address bytes (version byte + hash160)
    function _getP2SHAddressFromScript(
        bytes memory redeemScript,
        bool isMainnet
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = HELPER_SCRIPT_GET_P2SH_ADDRESS_FROM_SCRIPT;
        inputs[3] = _bytesToHexString(redeemScript);
        inputs[4] = isMainnet ? "true" : "false";

        bytes memory result = vm.ffi(inputs);
        return result;
    }

    /// @notice Converts bytes to hex string without 0x prefix
    /// @param data The bytes to convert
    /// @return The hex string
    function _bytesToHexString(
        bytes memory data
    ) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(data.length * 2);
        for (uint i = 0; i < data.length; i++) {
            result[i * 2] = hexChars[uint8(data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(result);
    }
}
