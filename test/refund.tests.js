const FlyoverProviderContract = artifacts.require('FlyoverProviderContract');
const LiquidityProviderContract = artifacts.require('LiquidityProviderContract');
const PeginContract = artifacts.require('PeginContract');
const PegoutContract = artifacts.require('PegoutContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock');
const WalletMock = artifacts.require('WalletMock');
const truffleAssert = require('truffle-assertions');
const chai = require("chai");
const utils = require('../test/utils/index');
const truffleAssertions = require("truffle-assertions");

const BN = web3.utils.BN;
const chaiBN = require('chai-bn')(BN);
chai.use(chaiBN);

const expect = chai.expect;

contract('FlyoverProviderContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    const liquidityProviderRskAddress = accounts[0];
    let lpContractAddress;

    before(async () => {
        const proxy = await FlyoverProviderContract.deployed();
        instance = await FlyoverProviderContract.at(proxy.address);
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed();
        extractEvents = await utils.getDeepEventFinder(LiquidityProviderContract, PeginContract, PegoutContract);
        lpContractAddress = await LiquidityProviderContract.deployed().then(contract => contract.address);
    });

    beforeEach(async () => {
        await utils.ensureLiquidityProviderAvailable(instance, liquidityProviderRskAddress, utils.LP_COLLATERAL);
    });

    it ('should transfer value and refund remaining', async () => {
        let destAddr = accounts[1];
        let rskRefundAddress = accounts[2];
        let data = '0x00';
        let val = web3.utils.toBN(10);
        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(lpContractAddress);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let additionalFunds = web3.utils.toBN(1000000000000);
        let peginAmount = val.add(quote.callFee).add(additionalFunds);
       
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 300).substring(2));
        let nConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 600).substring(2));
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader =     '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime +     '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            utils.asArray(quote),
            {value : val}
        );

        let currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        let amount = await instance.registerPegIn.call(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        ).then(extractEvents);

        let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let finalLBCBalance = await web3.eth.getBalance(lpContractAddress);
        let finalUserBalance = await web3.eth.getBalance(destAddr);
        let finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lbcBal = web3.utils.toBN(finalLBCBalance).sub(web3.utils.toBN(initialLBCBalance));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let refBal = web3.utils.toBN(finalRefundBalance).sub(web3.utils.toBN(initialRefundBalance));
        truffleAssert.eventEmitted(tx, "Refund", {
            dest: rskRefundAddress,
            amount: additionalFunds,
            success: true
        });
        expect(peginAmount).to.be.a.bignumber.eq(amount);
        expect(usrBal).to.be.a.bignumber.eq(val);
        expect(lbcBal).to.be.a.bignumber.eq(peginAmount.sub(additionalFunds));
        expect(lpBal).to.be.a.bignumber.eq(peginAmount.sub(additionalFunds));
        expect(refBal).to.be.a.bignumber.eq(additionalFunds);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should refund remaining amount to LP in case refunding to quote.rskRefundAddress fails', async () => {
        let walletMock = await WalletMock.new();
        await walletMock.setRejectFunds(true);
        
        let destAddr = accounts[1];
        let rskRefundAddress = walletMock.address;
        let data = '0x00';
        let val = web3.utils.toBN(10);
        let quote = utils.getTestQuote(
            instance.address,
            destAddr,
            data,
            liquidityProviderRskAddress,
            rskRefundAddress, // transfer to rskRefundAddress should revert
            val);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(lpContractAddress);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let additionalFunds = web3.utils.toBN(1000000000000);
        let peginAmount = val.add(quote.callFee).add(additionalFunds);

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 300).substring(2));
        let nConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 600).substring(2));
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader =     '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime +     '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            utils.asArray(quote),
            {value : val}
        );

        let currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        let amount = await instance.registerPegIn.call(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        ).then(extractEvents);

        let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let finalLBCBalance = await web3.eth.getBalance(lpContractAddress);
        let finalUserBalance = await web3.eth.getBalance(destAddr);
        let finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lbcBal = web3.utils.toBN(finalLBCBalance).sub(web3.utils.toBN(initialLBCBalance));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let refBal = web3.utils.toBN(finalRefundBalance).sub(web3.utils.toBN(initialRefundBalance));
        truffleAssert.eventEmitted(tx, "Refund", {
            dest: rskRefundAddress,
            amount: additionalFunds,
            success: false
        });
        truffleAssert.eventEmitted(tx, "BalanceIncrease", {
            dest: liquidityProviderRskAddress,
            amount: additionalFunds
        });
        expect(peginAmount).to.be.a.bignumber.eq(amount);
        expect(usrBal).to.be.a.bignumber.eq(val);
        expect(lbcBal).to.be.a.bignumber.eq(peginAmount);
        expect(lpBal).to.be.a.bignumber.eq(peginAmount);
        expect(refBal).to.be.a.bignumber.eq(web3.utils.toBN(0));
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should refund user on failed call', async () => {
        let val = web3.utils.toBN(1000000000000);
        let rskRefundAddress = accounts[2];
        let destAddr = mock.address;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = quote.val.add(quote.callFee);
        
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 300).substring(2));
        let nConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 600).substring(2));
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader =     '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime +     '0000000000000000';

        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            utils.asArray(quote),
            {value : quote.val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        expect(quote.val).to.be.a.bignumber.eq(currentLPBalance.sub(initialLPBalance));

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        ).then(extractEvents);

        let finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        truffleAssert.eventEmitted(tx, "Refund", {
            dest: rskRefundAddress,
            amount: quote.val,
            success: true
        });
        expect(lpBal).to.be.a.bignumber.eq(quote.val.add(quote.callFee));
        expect(usrBal).to.be.a.bignumber.eq(peginAmount.sub(quote.callFee));
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should refund user on missed call', async () => {
        let val = web3.utils.toBN(1000000000000);
        let rskRefundAddress = accounts[2];
        let destAddr = mock.address;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);
        quote.penaltyFee = web3.utils.toBN(10);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let initialAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(quote.penaltyFee.div(web3.utils.toBN(10)));
        let initialLbcBalance = await web3.eth.getBalance(lpContractAddress);
        let peginAmount = quote.val.add(quote.callFee);
        
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 300).substring(2));
        let nConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 600).substring(2));
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader =     '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime +     '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        ).then(extractEvents);

        let finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let finalAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        let finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let finalLbcBalance = await web3.eth.getBalance(lpContractAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let altBal = web3.utils.toBN(finalAltBalance).sub(web3.utils.toBN(initialAltBalance));
        let lpCol = web3.utils.toBN(initialLPDeposit).sub(web3.utils.toBN(finalLPDeposit));
        truffleAssert.eventEmitted(tx, "Refund", {
            dest: rskRefundAddress,
            amount: web3.utils.toBN(1000000000001),
            success: true,
            quoteHash: quoteHash,
        });
        expect(usrBal).to.be.a.bignumber.eq(peginAmount);
        expect(altBal).to.be.a.bignumber.eq(web3.utils.toBN(reward));
        expect(lpCol).to.be.a.bignumber.eq(quote.penaltyFee);
        expect(finalLbcBalance).to.be.a.bignumber.eq(initialLbcBalance);
    });

    it ('should no one be refunded in registerPegIn on missed call in case refunding to quote.rskRefundAddress fails', async () => {
        let walletMock = await WalletMock.new();
        await walletMock.setRejectFunds(true);
        
        let val = web3.utils.toBN(1000000000000);
        let registerPegInCaller = accounts[2];
        let rskRefundAddress = walletMock.address;
        let destAddr = mock.address;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let quote = utils.getTestQuote(
            instance.address,
            destAddr,
            data,
            liquidityProviderRskAddress,
            rskRefundAddress,
            val);
        quote.penaltyFee = web3.utils.toBN(10);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let peginAmount = quote.val.add(quote.callFee);

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let reward = Math.floor(quote.penaltyFee.div(web3.utils.toBN(10)));
        let firstConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 300).substring(2));
        let nConfirmationTime = utils.reverseHexBytes(web3.utils.toHex(quote.agreementTime + 600).substring(2));
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader =     '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime +     '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let initialCallerBalance = await instance.getBalance(registerPegInCaller);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLbcBalance = await web3.eth.getBalance(lpContractAddress);

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height,
            { from: registerPegInCaller }
        ).then(extractEvents);

        let finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let finalCallerBalance = await instance.getBalance(registerPegInCaller);
        let finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let finalLbcBalance = await web3.eth.getBalance(lpContractAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let callerBal = web3.utils.toBN(finalCallerBalance).sub(web3.utils.toBN(initialCallerBalance));
        let lpCol = web3.utils.toBN(initialLPDeposit).sub(web3.utils.toBN(finalLPDeposit));
        truffleAssert.eventEmitted(tx, "Refund", {
            dest: rskRefundAddress,
            amount: web3.utils.toBN(1000000000001),
            success: false,
            quoteHash: quoteHash,
        });
        expect(usrBal).to.be.a.bignumber.eq(web3.utils.toBN(0));
        expect(callerBal).to.be.a.bignumber.eq(web3.utils.toBN(reward));
        expect(lpCol).to.be.a.bignumber.eq(quote.penaltyFee);
        expect(finalLbcBalance).to.be.a.bignumber.eq(web3.utils.toBN(initialLbcBalance).add(peginAmount));
    });
});
