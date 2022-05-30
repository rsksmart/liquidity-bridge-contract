const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')
const truffleAssert = require('truffle-assertions');
var chai = require("chai");
const utils = require('../test/utils/index');

const BN = web3.utils.BN;
const chaiBN = require('chai-bn')(BN);
chai.use(chaiBN);

const expect = chai.expect;

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    const liquidityProviderRskAddress = accounts[0];

    before(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed()
    });

    beforeEach(async () => {
        await utils.ensureLiquidityProviderAvailable(instance, liquidityProviderRskAddress, utils.LP_COLLATERAL);
    });

    it ('should not penalize with late deposit', async () => {
        let val = web3.utils.toBN(1000000000000);
        let destAddr = mock.address;
        let rskRefundAddress = accounts[2];
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);

        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);
        quote.penaltyFee = web3.utils.toBN(10);
        quote.timeForDeposit = 1;

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let peginAmount = val.add(quote.callFee);

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        truffleAssert.eventNotEmitted(tx, "Penalized");
        expect(usrBal).to.be.a.bignumber.eq(peginAmount);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should not penalize with insufficient deposit', async () => {
        let val = web3.utils.toBN(1000000000000);
        let destAddr = mock.address;
        let rskRefundAddress = accounts[2];
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);

        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);
        quote.penaltyFee = web3.utils.toBN(10);
        let peginAmount = val.add(quote.callFee).sub(web3.utils.toBN(1));

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        truffleAssert.eventNotEmitted(tx, "Penalized");
        expect(usrBal).to.be.a.bignumber.eq(peginAmount);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should penalize on late call', async () => {
        let val = web3.utils.toBN(10);
        let rskRefundAddress = accounts[2];
        let destAddr = accounts[1];

        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            null, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);
        quote.penaltyFee = web3.utils.toBN(10);
        quote.callTime = 1;
        let peginAmount = quote.val.add(quote.callFee);

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;

        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(quote.penaltyFee.div(web3.utils.toBN(10)));

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);
    
        await utils.timeout(5000);

        await instance.callForUser(
            utils.asArray(quote),
            {value : quote.val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(quote.destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lpCol = web3.utils.toBN(initialLPDeposit).sub(web3.utils.toBN(finalLPDeposit));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        truffleAssert.eventEmitted(tx, "Penalized", {
            liquidityProvider: liquidityProviderRskAddress,
            penalty: quote.penaltyFee,
            quoteHash: quoteHash
        }); 
        expect(usrBal).to.be.a.bignumber.eq(quote.val);
        expect(lpCol).to.be.a.bignumber.eq(quote.penaltyFee);
        expect(lpBal).to.eql(web3.utils.toBN(reward).add(peginAmount));
    });

    it ('should not underflow when penalty is higher than collateral', async () => {
        let val = web3.utils.toBN(10);
        let rskRefundAddress = accounts[2];
        let destAddr = accounts[1];

        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            null, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            val);
        quote.callTime = 1;
        quote.penaltyFee = web3.utils.toBN(110);
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;

        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = quote.val.add(quote.callFee);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let rewardPercentage = await instance.getRewardPercentage();
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        
        let reward = Math.floor(Math.min(initialLPDeposit, quote.penaltyFee) * rewardPercentage / 100);
        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);
        
        await utils.timeout(5000);
        
        await instance.callForUser(
            utils.asArray(quote),
            {value : quote.val}
        );
        
        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);
        
        let tx = await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );
        
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        truffleAssert.eventEmitted(tx, "Penalized", {
            liquidityProvider: liquidityProviderRskAddress,
            penalty: initialLPDeposit,
            quoteHash: quoteHash
        });
        expect(web3.utils.toBN(0)).to.be.a.bignumber.eq(finalLPDeposit);
        expect(lpBal).to.eql(web3.utils.toBN(reward).add(peginAmount));
    });
});
