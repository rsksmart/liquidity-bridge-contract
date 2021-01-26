const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    
    beforeEach(async () => {
        instance = await LiquidityBridgeContract.deployed();
        //bridgeMockInstance = await BridgeMock.deployed();
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
        let destAddr = web3.eth.currentProvider.addresses[1];
        let existingBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x001';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let data = '0x0';
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 3;
        let nonce = 0;

        await instance.callForUser(
            fedBtcAddress,
            liquidityProviderRskAddress,
            destAddr,
            data,
            penaltyFee,
            successFee,
            gasLimit,
            nonce,
            val,
            {value : val}
        );

        newBalance = await web3.eth.getBalance(destAddr);

        assert.equal(val, parseInt(newBalance) - parseInt(existingBalance));
    });

    it ('should call contract for user', async () => {
            let val = 0;
            let destAddr = mock.address;
            let fedBtcAddress = '0x001';
            let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
            let penaltyFee = 0;
            let successFee = 1;
            let gasLimit = 50000;
            let nonce = 0;
            let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);

            await mock.set(0);

            await instance.callForUser(
                fedBtcAddress,
                liquidityProviderRskAddress,
                destAddr,
                data,
                penaltyFee,
                successFee,
                gasLimit,
                nonce,
                val
            );

            current = await mock.check();

            assert.equal(12, current.toNumber());
    });

    /*
    it('should create pre hash', async () => {
        // Arrange
        let fedBtcAddress = '0x001';
        let liquidityProviderRskAddress = '0x0000000000000000000000000000000000000001';
        let callContract = '0x0000000000000000000000000000000000000002';
        let callContractArguments = '0x002'; 
        let penaltyFee = 1;
        let successFee = 2;
        let gasLimit = 3;
        let nonce = 0;
        let valueToTransfer = 10;

        // Act
        let preHash = await instance.hash(
            fedBtcAddress, 
            liquidityProviderRskAddress, 
            callContract, 
            callContractArguments, 
            penaltyFee, 
            successFee, 
            gasLimit, 
            nonce, 
            valueToTransfer
        );
        
        // Assert
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','int','int','int','int','int'], 
            [fedBtcAddress, liquidityProviderRskAddress, callContract, callContractArguments, penaltyFee, successFee, gasLimit, nonce, valueToTransfer]
        );
        let expectedHash = await web3.utils.keccak256(encodedParams);
        
        assert.equal(expectedHash, preHash);
    });

    it('should create derivation hash', async () => {
        // Arrange
        let preHash = '0x53230a92e3ad30bd6a9394e4aa15e7e4ad6edf0d04d5f2fd9b0e1551d600ed28';
        let userBtcRefundAddress = '0x0005';
        let liquidityProviderBtcAddress = '0x0006';

        // Act
        let derivationHash = await instance.getDerivationHash(
            preHash, 
            userBtcRefundAddress, 
            liquidityProviderBtcAddress
        );

        // Assert
        let expectedHash = await web3.utils.keccak256(
            [preHash, userBtcRefundAddress.substring(2), 
             instance.address.substring(2), 
             liquidityProviderBtcAddress.substring(2)
            ].join('')
        );
                
        assert.equal(expectedHash, derivationHash);
    });

    it('should register fast bridge btc transaction', async () => {
        // Arrange
        let btcRawTransaction = '0x001001';
        let partialMerkleTree = '0x002001';
        let height = 100; 
        let userBtcRefundAddress = '0x005';
        let liquidityProviderBtcAddress = '0x006';
        let preHash = '0x53230a92e3ad30bd6a9394e4aa15e7e4ad6edf0d04d5f2fd9b0e1551d600ed28';

        let derivationHash = await instance.getDerivationHash(
            preHash, 
            userBtcRefundAddress, 
            liquidityProviderBtcAddress
        );
        let initialAmount = 90;
        let returnStatus = 20;

        await instance.setDerivationHashBalance(derivationHash, initialAmount);
        await bridgeMockInstance.setReturnStatus(preHash, returnStatus);

        // Act
        let transferredAmount = await instance.registerFastBridgeBtcTransaction.call(
            btcRawTransaction, 
            partialMerkleTree, 
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            preHash
        );
        assert.equal(returnStatus, transferredAmount);
        
        await instance.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            partialMerkleTree, 
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            preHash
        );
        
        // Assert
        let expectedAmount = initialAmount - returnStatus;
        let finalAmount = await instance.getDerivationHashBalance.call(derivationHash);

        assert.equal(expectedAmount, finalAmount);
    });

    it('should not register fast bridge btc transaction, Bridge responds with error', async () => {
        // Arrange
        let btcRawTransaction = '0x001001';
        let partialMerkleTree = '0x002001';
        let height = 100; 
        let userBtcRefundAddress = '0x005';
        let liquidityProviderBtcAddress = '0x006';
        let preHash = '0x53230a92e3ad30bd6a9394e4aa15e7e4ad6edf0d04d5f2fd9b0e1551d600ed28';

        let derivationHash = await instance.getDerivationHash(
            preHash, 
            userBtcRefundAddress, 
            liquidityProviderBtcAddress
        );
        let initialAmount = 90;
        let returnStatus = -1;

        await instance.setDerivationHashBalance(derivationHash, initialAmount);
        await bridgeMockInstance.setReturnStatus(preHash, returnStatus);

        // Act
        let transferredAmount = await instance.registerFastBridgeBtcTransaction.call(
            btcRawTransaction, 
            partialMerkleTree, 
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            preHash
        );
        assert.equal(returnStatus, transferredAmount);

        await instance.registerFastBridgeBtcTransaction(
            btcRawTransaction, 
            partialMerkleTree, 
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress,
            preHash
        );
        
        // Assert
        let finalAmount = await instance.getDerivationHashBalance.call(derivationHash);
        assert.equal(initialAmount, finalAmount);
    });*/
});
