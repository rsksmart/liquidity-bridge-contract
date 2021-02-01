const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    
    beforeEach(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed()
    });

    it ('should register liquidity provider', async () => {
        let val = 100;
        let currAddr = web3.eth.currentProvider.getAddress();
        let existing = await instance.getDeposit(currAddr); // TODO withdraw instead

        await instance.register({value : val});

        let current = await instance.getDeposit(currAddr);
        let registered = current.toNumber() - existing.toNumber();

        assert.equal(val, registered);
    });

    it ('should transfer value for user', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let previousUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x001';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let previousLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let data = '0x0';
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 3;
        let nonce = 0;
        let peginAmount = val + successFee;
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val]
        );
        let preHash = await web3.utils.keccak256(encodedParams);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.callForUser(
            fedBtcAddress,
            liquidityProviderRskAddress,
            rskRefundAddress,
            destAddr,
            data,
            penaltyFee,
            successFee,
            gasLimit,
            nonce,
            val,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        newUserBalance = await web3.eth.getBalance(destAddr);
        previousLBCBalance = await web3.eth.getBalance(instance.address);

        assert.equal(currentLPBalance.toNumber(), previousLPBalance.toNumber());

        amount = await instance.registerFastBridgeBtcTransaction.call(
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            rskRefundAddress,
            preHash,
            successFee,
            penaltyFee
        );

        await instance.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            rskRefundAddress,
            preHash,
            successFee,
            penaltyFee
        );

        newLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        newLBCBalance = await web3.eth.getBalance(instance.address);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(newUserBalance) - parseInt(previousUserBalance));
        assert.equal(peginAmount, parseInt(newLBCBalance) - parseInt(previousLBCBalance));
        assert.equal(peginAmount, newLPBalance.toNumber() - previousLPBalance.toNumber());
    });


    it ('should call contract for user', async () => {
        let val = 0;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let destAddr = mock.address;
        let fedBtcAddress = '0x001';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 50000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);
        let previousLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = val + successFee;
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val]
        );
        let preHash = await web3.utils.keccak256(encodedParams);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});
        await mock.set(0);

        await instance.callForUser(
            fedBtcAddress,
            liquidityProviderRskAddress,
            rskRefundAddress,
            destAddr,
            data,
            penaltyFee,
            successFee,
            gasLimit,
            nonce,
            val
        );

        previousLBCBalance = await web3.eth.getBalance(instance.address);
        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);        

        assert.equal(currentLPBalance.toNumber(), previousLPBalance.toNumber());

        amount = await instance.registerFastBridgeBtcTransaction.call(
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            rskRefundAddress,
            preHash,
            successFee,
            penaltyFee
        );

        await instance.registerFastBridgeBtcTransaction(
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            rskRefundAddress,
            preHash,
            successFee,
            penaltyFee
        );

        newLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        newLBCBalance = await web3.eth.getBalance(instance.address);

        assert.equal(peginAmount, amount);
        assert.equal(peginAmount, amount.toNumber());
        assert.equal(peginAmount, newLPBalance.toNumber() - previousLPBalance.toNumber());
        assert.equal(peginAmount, parseInt(newLBCBalance) - parseInt(previousLBCBalance));

        currentValue = await mock.check();

        assert.equal(12, currentValue.toNumber());
    });
});
