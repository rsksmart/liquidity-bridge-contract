const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')
const truffleAssert = require('truffle-assertions');
var chai = require("chai");

const BN = web3.utils.BN;
const chaiBN = require('chai-bn')(BN);
chai.use(chaiBN);

const expect = chai.expect;

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    
    before(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed()
    });

    it ('should register liquidity provider', async () => {
        let val = new BN(100);
        let currAddr = accounts[0];
        let existing = await instance.getCollateral(currAddr); 

        await instance.register({value : val});

        let current = await instance.getCollateral(currAddr);
        let registered = current.sub(existing);

        expect(val).to.be.a.bignumber.eq(registered);
    });


    it ('should not penalize with late deposit', async () => {
        let val = web3.utils.toBN(1000000000000);
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = accounts[0];
        let rskRefundAddress = accounts[2];
        let callFee = web3.utils.toBN(1);
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = val.add(callFee);
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 1;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
            fedBtcAddress, 
            lbcAddress, 
            liquidityProviderRskAddress, 
            userBtcRefundAddress, 
            rskRefundAddress, 
            liquidityProviderBtcAddress, 
            callFee, 
            penaltyFee,
            destAddr, 
            data, 
            gasLimit, 
            nonce, 
            val, 
            agreementTime, 
            timeForDeposit, 
            callTime, 
            depositConfirmations,
            callOnRegister
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        expect(usrBal).to.be.a.bignumber.eq(peginAmount);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should not penalize with insufficient deposit', async () => {
        let val = 1000000000000;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = accounts[0];
        let rskRefundAddress = accounts[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee)).sub(web3.utils.toBN(1));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
            fedBtcAddress, 
            lbcAddress, 
            liquidityProviderRskAddress, 
            userBtcRefundAddress, 
            rskRefundAddress, 
            liquidityProviderBtcAddress, 
            callFee, 
            penaltyFee,
            destAddr, 
            data, 
            gasLimit, 
            nonce, 
            val, 
            agreementTime, 
            timeForDeposit, 
            callTime, 
            depositConfirmations,
            callOnRegister
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        expect(usrBal).to.be.a.bignumber.eq(peginAmount);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should penalize on late call', async () => {
        let val = web3.utils.toBN(10);
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = accounts[2];
        let destAddr = accounts[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = accounts[0];
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 30000;
        let nonce = 0;
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 1;
        let depositConfirmations = 10;
        let penaltyFee = web3.utils.toBN(10);
        let callOnRegister = false;
        let quote = [
            fedBtcAddress, 
            lbcAddress, 
            liquidityProviderRskAddress, 
            userBtcRefundAddress, 
            rskRefundAddress, 
            liquidityProviderBtcAddress, 
            callFee, 
            penaltyFee,
            destAddr, 
            data, 
            gasLimit, 
            nonce, 
            val, 
            agreementTime, 
            timeForDeposit, 
            callTime, 
            depositConfirmations,
            callOnRegister
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(penaltyFee / 10);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lpCol = web3.utils.toBN(initialLPDeposit).sub(web3.utils.toBN(finalLPDeposit));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        expect(usrBal).to.be.a.bignumber.eq(val);
        expect(lpCol).to.be.a.bignumber.eq(penaltyFee);
        expect(lpBal).to.eql(web3.utils.toBN(reward).add(peginAmount));
    });

    it ('should not undeflow when penalty is higher than collateral', async () => {
        let val = web3.utils.toBN(10);
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = accounts[2];
        let destAddr = accounts[1];
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = accounts[0];
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 300000;
        let nonce = 0;
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 1;
        let depositConfirmations = 10;
        let penaltyFee = web3.utils.toBN(110);
        let callOnRegister = false;
        let quote = [
            fedBtcAddress, 
            lbcAddress, 
            liquidityProviderRskAddress, 
            userBtcRefundAddress, 
            rskRefundAddress, 
            liquidityProviderBtcAddress, 
            callFee, 
            penaltyFee,
            destAddr, 
            data, 
            gasLimit, 
            nonce, 
            val, 
            agreementTime, 
            timeForDeposit, 
            callTime, 
            depositConfirmations,
            callOnRegister
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(penaltyFee / 10);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        let tx = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        truffleAssert.eventEmitted(tx, "Penalized");        
        expect(new BN(0)).to.be.a.bignumber.eq(finalLPDeposit);
        expect(lpBal).to.eql(web3.utils.toBN(reward).add(peginAmount));
    });
});
