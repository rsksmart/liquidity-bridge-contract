const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')
const truffleAssert = require('truffle-assertions');

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    
    before(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed()
    });

    it ('should register liquidity provider', async () => {
        let val = 100;
        let currAddr = accounts[0];
        let existing = await instance.getCollateral(currAddr); 

        await instance.register({value : val});

        let current = await instance.getCollateral(currAddr);
        let registered = current.toNumber() - existing.toNumber();

        assert.equal(val, registered);
    });

    it ('should transfer value and refund remaining', async () => {
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
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let data = '0x00';
        let callFee = web3.utils.toBN(1);
        let gasLimit = 150000;
        let nonce = 0;
        let additionalFunds = web3.utils.toBN(1000000000000);
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee)).add(web3.utils.toBN(additionalFunds));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
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

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        let tx = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lbcBal = web3.utils.toBN(finalLBCBalance).sub(web3.utils.toBN(initialLBCBalance));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let refBal = web3.utils.toBN(finalRefundBalance).sub(web3.utils.toBN(initialRefundBalance));
        truffleAssert.eventEmitted(tx, "Refund");
        expect(peginAmount.toNumber()).to.eql(amount.toNumber());
        expect(usrBal.toNumber()).to.eq(val.toNumber());
        expect(lbcBal.toNumber()).to.eql(peginAmount.sub(additionalFunds).toNumber());
        expect(lpBal.toNumber()).to.eql(peginAmount.sub(additionalFunds).toNumber());
        expect(refBal.toNumber()).to.eql(additionalFunds.toNumber());
        expect(finalLPDeposit).to.eql(initialLPDeposit);
    });

    it ('should refund user on failed call', async () => {
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
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
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

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(val, parseInt(currentLPBalance) - parseInt(initialLPBalance));

        let tx = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        truffleAssert.eventEmitted(tx, "Refund");
        expect(lpBal).to.eql(val.add(web3.utils.toBN(callFee)));
        expect(usrBal.toNumber()).to.eq(peginAmount.sub(web3.utils.toBN(callFee)).toNumber());
        expect(finalLPDeposit).to.eql(initialLPDeposit);
    });

    it ('should refund user on missed call', async () => {
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
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = web3.utils.toBN(val).add(web3.utils.toBN(callFee));
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
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
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = web3.utils.toBN(Math.floor(penaltyFee / 10));
        let initialLbcBalance = await web3.eth.getBalance(instance.address);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        let tx = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        finalLbcBalance = await web3.eth.getBalance(instance.address);

        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        let lpBal = web3.utils.toBN(finalAltBalance).sub(web3.utils.toBN(initialAltBalance));
        let lpCol = web3.utils.toBN(initialLPDeposit).sub(web3.utils.toBN(finalLPDeposit));
        truffleAssert.eventEmitted(tx, "Refund");
        expect(usrBal.toNumber()).to.eq(peginAmount.toNumber());
        expect(lpBal.toNumber()).to.eql(reward.toNumber());
        expect(lpCol.toNumber()).to.eql(penaltyFee.toNumber());
        expect(finalLbcBalance).to.eql(initialLbcBalance);
    });
});
