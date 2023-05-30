const LiquidityBridgeContract = artifacts.require("LiquidityBridgeContract");
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require("Mock");
const SignatureValidatorMock = artifacts.require("SignatureValidatorMock");

var chai = require("chai");
const truffleAssertions = require("truffle-assertions");
const utils = require("../test/utils/index");
const BN = web3.utils.BN;
const chaiBN = require("chai-bn")(BN);
chai.use(chaiBN);
const expect = chai.expect;

contract("LiquidityBridgeContract", async (accounts) => {
  let instance;
  let bridgeMockInstance;
  let signatureValidatorInstance;
  const liquidityProviderRskAddress = accounts[0];
  const MAX_UINT32 = Math.pow(2, 32) - 1;
  var providerList = [];
  before(async () => {
    const proxy = await LiquidityBridgeContract.deployed();
    instance = await LiquidityBridgeContract.at(proxy.address);
    bridgeMockInstance = await BridgeMock.deployed();
    mock = await Mock.deployed();
    signatureValidatorInstance = await SignatureValidatorMock.deployed();
  });

  beforeEach(async () => {
    await utils.ensureLiquidityProviderAvailable(
      instance,
      liquidityProviderRskAddress,
      utils.LP_COLLATERAL
    );
  });

  it("should register liquidity provider", async () => {
    let currAddr = accounts[8];
    let existing = await instance.getCollateral(currAddr);

    let tx = await instance.register(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      "both",
      { from: currAddr, value: utils.LP_COLLATERAL }
    );
    providerList.push(tx.logs[0].args.id.toNumber());

    let current = await instance.getCollateral(currAddr);
    let registered = current.sub(existing);

    truffleAssertions.eventEmitted(tx, "Register", {
      from: currAddr,
      amount: utils.LP_COLLATERAL,
    });
    // TODO this multiplication by 2 is a temporal fix until we define solution with product team
    expect(utils.LP_COLLATERAL).to.be.a.bignumber.eq(
      registered.mul(web3.utils.toBN(2))
    );
  });
  it("Should fail on register if bad parameters", async () => {
    let currAddr = accounts[5];

    await truffleAssertions.reverts(
      instance.register("", 0, 0, 0, 10, 100, "", true, "both", {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      }),
      "LBC010"
    );
  });
  it("Should fail on register if not deposit the minimum collateral", async () => {
    let currAddr = accounts[5];

    await truffleAssertions.reverts(
      instance.register(
        "First contract",
        10,
        7200,
        3600,
        10,
        100,
        "http://localhost/api",
        true,
        "both",
        { from: currAddr, value: web3.utils.toBN(0) }
      ),
      "LBC008"
    );
  });

  it("should not register lp with not enough collateral", async () => {
    const minCollateral = await instance.getMinCollateral();

    const lessThanMinimum = minCollateral.sub(utils.ONE_COLLATERAL);
    await truffleAssertions.reverts(
      instance.register(
        "First contract",
        10,
        7200,
        3600,
        10,
        100,
        "http://localhost/api",
        true,
        "both",
        { from: accounts[1], value: lessThanMinimum }
      ),
      "LBC008"
    );
  });

  it("should validate provider limits on register", async () => {
    const minCollateral = await instance.getMinCollateral();

    await truffleAssertions.reverts(
      instance.register(
        "First contract",
        10,
        7200,
        3600,
        10,
        web3.utils.toBN("1000000000000000001"),
        "http://localhost/api",
        true,
        "both",
        { from: accounts[1], value: minCollateral }
      ),
      "LBC016"
    );
  });

  it("should fail to register liquidity provider from a contract", async () => {
    let currAddr = accounts[9];

    await truffleAssertions.fails(
      mock.callRegister(instance.address, {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      })
    );
  });

  it("should get registered liquidity providers", async () => {
    let currAddr = accounts[1];

    let tx = await instance.register(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      "both",
      {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      }
    );
    providerList.push(tx.logs[0].args.id.toNumber());

    truffleAssertions.eventEmitted(tx, "Register", {
      from: currAddr,
      amount: utils.LP_COLLATERAL,
    });
    let currAddr2 = accounts[2];

    let tx2 = await instance.register(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      "both",
      {
        from: currAddr2,
        value: utils.LP_COLLATERAL,
      }
    );
    providerList.push(tx2.logs[0].args.id.toNumber());

    truffleAssertions.eventEmitted(tx2, "Register", {
      from: currAddr2,
      amount: utils.LP_COLLATERAL,
    });
    let providers = await instance.getProviders(providerList);
    expect(providers.length).to.be.greaterThan(0);
    expect(accounts).to.includes(providers[0].provider);
    expect(accounts).to.includes(providers[1].provider);
    expect(accounts).to.includes(providers[2].provider);
  });
  it("should get providerIds", async () => {
    let providerId = await instance.getProviderIds();
    expect(providerId.toNumber() == providerList.length);
  });
  it("should disable provider", async () => {
    await instance.setProviderStatus(1, false, { from: accounts[0] });
    let provider = await instance.getProviders([1]);
    assert.equal(provider[0].status, false, "Provider status should be false");
  });
  it("should enable provider", async () => {
    await instance.setProviderStatus(1, true, { from: accounts[0] });
    let provider = await instance.getProviders([1]);
    assert.equal(provider[0].status, true, "Provider status should be false");
  });
  it("should disable provider as provider owner", async () => {
    await instance.setProviderStatus(1, false, { from: accounts[0] });
    let provider = await instance.getProviders([1]);
    assert.equal(provider[0].status, false, "Provider status should be false");
  });
  it("should fail disabling provider as non owners", async () => {
    await truffleAssertions.reverts(
      instance.setProviderStatus(1, false, { from: accounts[1] })
    );
  });
  it("should match lp address with address retrieved from ecrecover", async () => {
    let quote = utils.getTestQuote(
      instance.address,
      accounts[1],
      "0x00",
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );

    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let sig = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let signer = web3.eth.accounts.recover(quoteHash, sig);

    expect(liquidityProviderRskAddress).to.be.equal(signer);

    let sameSigner = await signatureValidatorInstance.verify(
      liquidityProviderRskAddress,
      quoteHash,
      sig
    );
    expect(sameSigner).to.be.true;
  });

  it("should call contract for user", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN("20000000000000000000") // 20 RBTCs
    );

    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let peginAmount = quote.val.add(quote.callFee);
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(instance.address);
    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);

    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setPegin(quoteHash, { value: peginAmount });
    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(
      height + quote.depositConfirmations - 1,
      nHeader
    );
    await mock.set(0);

    let initialLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );
    let cfuTx = await instance.callForUser(utils.asArray(quote), {
      value: quote.val,
    });

    let currentLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );

    expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

    let amount = await instance.registerPegIn.call(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    await instance.registerPegIn(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
    let finalLBCBalance = await web3.eth.getBalance(instance.address);
    let finalLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let lpBal = web3.utils
      .toBN(finalLPBalance)
      .sub(web3.utils.toBN(initialLPBalance));
    let lbcBal = web3.utils
      .toBN(finalLBCBalance)
      .sub(web3.utils.toBN(initialLBCBalance));
    expect(peginAmount).to.be.a.bignumber.eq(amount);
    expect(peginAmount).to.be.a.bignumber.eq(lpBal);
    expect(peginAmount).to.be.a.bignumber.eq(lbcBal);
    expect(initialLPDeposit).to.be.a.bignumber.eq(finalLPDeposit);
    truffleAssertions.eventEmitted(cfuTx, "CallForUser", {
      from: quote.liquidityProviderRskAddress,
      dest: quote.destAddr,
      value: quote.val,
      data: quote.data,
      success: true,
      quoteHash: quoteHash,
    });
    let finalValue = await mock.check();
    expect(web3.utils.toBN(12)).to.be.a.bignumber.eq(finalValue);
  });

  it("should fail when withdraw amount greater than of sender balance", async () => {
    await instance.deposit({ value: web3.utils.toBN("100000000") });
    await truffleAssertions.reverts(
      instance.withdraw(web3.utils.toBN("99999999999999999999")),
      "LBC019"
    );
    await instance.withdraw(web3.utils.toBN("100000000"));
  });

  it("should fail when liquidityProdvider try to withdraw collateral without resign postion as liquidity provider before", async () => {
    await instance.addCollateral({ value: web3.utils.toBN("100000000") });
    await truffleAssertions.reverts(
      instance.withdrawCollateral(),
      "LBC021"
    );
    await instance.resign();
    await instance.withdrawCollateral();
  });

  it("should fail when liquidityProdvider resign two times", async () => {
    await instance.resign();
    await truffleAssertions.reverts(instance.resign(), "LBC001");
    await instance.withdrawCollateral();
  });

  it("should deposit a value to increase balance of liquidity provider", async () => {
    const value = web3.utils.toBN("100000000");
    const tx = await instance.deposit({ value });
    truffleAssertions.eventEmitted(tx, "BalanceIncrease", {
      dest: liquidityProviderRskAddress,
      amount: value,
    });
  });

  it("should fail on contract call due to invalid lbc address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      accounts[0], // non-LBC address
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC051"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC051"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC051"
    );
  });

  it("should fail on contract call due to invalid contract address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = bridgeMockInstance.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC052"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC052"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC052"
    );
  });

  it("should fail on contract call due to invalid user btc refund address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );
    for (let addr of [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ]) {
      quote.userBtcRefundAddress = addr;

      await truffleAssertions.reverts(
        instance.hashQuote.call(utils.asArray(quote)),
        "LBC053"
      );

      await truffleAssertions.reverts(
        instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
        "LBC053"
      );

      await truffleAssertions.reverts(
        instance.registerPegIn.call(
          utils.asArray(quote),
          signature,
          btcRawTransaction,
          partialMerkleTree,
          height
        ),
        "LBC053"
      );
    }
  });

  it("should fail on contract call due to invalid lp btc address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    for (let addr of [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ]) {
      quote.liquidityProviderBtcAddress = addr;

      await truffleAssertions.reverts(
        instance.hashQuote.call(utils.asArray(quote)),
        "LBC054"
      );

      await truffleAssertions.reverts(
        instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
        "LBC054"
      );

      await truffleAssertions.reverts(
        instance.registerPegIn.call(
          utils.asArray(quote),
          signature,
          btcRawTransaction,
          partialMerkleTree,
          height
        ),
        "LBC054"
      );
    }
  });

  it("should fail on contract call due to quote value+fee being below min peg-in", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC055"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC055"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC055"
    );
  });

  it("should transfer value for user", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = accounts[1];
    let lbcAddress = instance.address;
    let quote = utils.getTestQuote(
      lbcAddress,
      destAddr,
      "0x00",
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(10)
    );

    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let initialUserBalance = await web3.eth.getBalance(destAddr);
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(instance.address);
    let peginAmount = quote.val.add(quote.callFee);
    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setPegin(quoteHash, { value: peginAmount });
    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(
      height + quote.depositConfirmations - 1,
      nHeader
    );
    let initialLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let cfuTx = await instance.callForUser(utils.asArray(quote), {
      value: quote.val,
    });

    let currentLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

    let amount = await instance.registerPegIn.call(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    await instance.registerPegIn(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
    let finalLBCBalance = await web3.eth.getBalance(instance.address);
    let finalUserBalance = await web3.eth.getBalance(destAddr);
    let finalLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let lbcBal = web3.utils
      .toBN(finalLBCBalance)
      .sub(web3.utils.toBN(initialLBCBalance));
    let lpBal = web3.utils
      .toBN(finalLPBalance)
      .sub(web3.utils.toBN(initialLPBalance));
    let usrBal = web3.utils
      .toBN(finalUserBalance)
      .sub(web3.utils.toBN(initialUserBalance));
    truffleAssertions.eventEmitted(cfuTx, "CallForUser", {
      from: quote.liquidityProviderRskAddress,
      dest: quote.destAddr,
      value: quote.val,
      data: quote.data,
      success: true,
      quoteHash: quoteHash,
    });
    expect(peginAmount).to.be.a.bignumber.eq(amount);
    expect(usrBal).to.be.a.bignumber.eq(quote.val);
    expect(lbcBal).to.be.a.bignumber.eq(peginAmount);
    expect(lpBal).to.be.a.bignumber.eq(peginAmount);
    expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
  });

  it("should resign", async () => {
    let lbcAddress = instance.address;
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(lbcAddress);
    let initialLPCol = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let resignTx = await instance.resign();
    let withdrawTx = await instance.withdraw(initialLPBalance);

    let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
    let currentLBCBalance = await web3.eth.getBalance(lbcAddress);

    let lbcCurrBal = web3.utils
      .toBN(initialLBCBalance)
      .sub(web3.utils.toBN(currentLBCBalance));
    expect(initialLPBalance).to.be.a.bignumber.eq(lbcCurrBal);
    expect(finalLPBalance).to.be.a.bignumber.eq(web3.utils.toBN(0));

    let withdrawCollateralTx = await instance.withdrawCollateral();

    let finalLPCol = await instance.getCollateral(liquidityProviderRskAddress);
    let finalLBCBalance = await web3.eth.getBalance(lbcAddress);
    let lbcBal = web3.utils
      .toBN(currentLBCBalance)
      .sub(web3.utils.toBN(finalLBCBalance));
    truffleAssertions.eventEmitted(resignTx, "Resigned", {
      from: liquidityProviderRskAddress,
    });
    truffleAssertions.eventEmitted(withdrawTx, "Withdrawal", {
      from: liquidityProviderRskAddress,
      amount: initialLPBalance,
    });
    truffleAssertions.eventEmitted(withdrawCollateralTx, "WithdrawCollateral", {
      from: liquidityProviderRskAddress,
      amount: initialLPCol,
    });
    expect(lbcBal).to.be.a.bignumber.eq(initialLPCol);
    expect(web3.utils.toBN(0)).to.be.a.bignumber.eq(finalLPCol);
  });

  it("Should refundPegOut", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    const getBalances = () =>
      Promise.all([
        instance.getBalance(liquidityProviderRskAddress),
        web3.eth.getBalance(instance.address),
      ]);

    const [userPegInBalanceBefore, contractBalanceBefore] = await getBalances();

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );
    quote.transferConfirmations = 0;

    // configure mocked block on mockBridge
    const block = await web3.eth.getBlock("latest");
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 600).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    const nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeader(block.timestamp, firstHeader);
    await bridgeMockInstance.setHeader(
      block.timestamp + quote.depositConfirmations - 1,
      nHeader
    );

    const msgValue = quote.value.add(quote.callFee);
    const pegOut = await instance.depositPegout(quote, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const [userPegInBalanceAfter, contractBalanceAfter] = await getBalances();

    expect(userPegInBalanceBefore.toString()).to.be.eq(
      userPegInBalanceAfter.toString()
    );
    expect(+contractBalanceAfter).to.be.eq(+contractBalanceBefore + msgValue.toNumber());

    const lpBalanceBefore = await web3.eth.getBalance(
      liquidityProviderRskAddress
    );
    const refund = await instance.refundPegOut(
      quote,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    const lpBalanceAfter = await web3.eth.getBalance(
      liquidityProviderRskAddress
    );
    const usedInGas = refund.receipt.gasUsed * refund.receipt.effectiveGasPrice;
    const refundedAmount = +quote.value + +quote.callFee;
    expect(+lpBalanceAfter).to.be.eq(
      +lpBalanceBefore + refundedAmount - usedInGas
    );
    truffleAssertions.eventEmitted(refund, "PegOutRefunded");
  });

  it("Should not allow user to re deposit a refunded quote", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(25)
    );
    quote.transferConfirmations = 0;
    quote.agreementTimestamp = Math.round(new Date().getTime() / 1000)

    // configure mocked block on mockBridge
    const block = await web3.eth.getBlock("latest");
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 600).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    const nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeader(block.timestamp, firstHeader);
    await bridgeMockInstance.setHeader(
      block.timestamp + quote.depositConfirmations - 1,
      nHeader
    );

    const msgValue = quote.value.add(quote.callFee);
    const pegOut = await instance.depositPegout(quote, { value: msgValue.toNumber() });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const refund = await instance.refundPegOut(
      quote,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    truffleAssertions.eventEmitted(refund, "PegOutRefunded");

    const secondDeposit = instance.depositPegout(quote, { value: msgValue.toNumber() });
    await truffleAssertions.reverts(secondDeposit, "LBC064");
  });

  it("Should validate that the quote was processed on refundPegOut", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address,
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );
    quote.transferConfirmations = 0;

    const refund = instance.refundPegOut(
      utils.asArray(quote),
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    await truffleAssertions.reverts(refund, "LBC042");
  });

  it("Should validate if the quote is expired date on refundPegOut", async () => {
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    const getBalances = () =>
      Promise.all([
        instance.getBalance(liquidityProviderRskAddress),
        web3.eth.getBalance(instance.address),
      ]);

    const [userPegInBalanceBefore, contractBalanceBefore] = await getBalances();

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );
    quote.transferConfirmations = 0;
    const additionalSecondsToExpire = 1
    quote.expireDate = Math.round(new Date().getTime() / 1000) + additionalSecondsToExpire;
    const msgValue = quote.value.add(quote.callFee);
    const pegOut = await instance.depositPegout(quote, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const [userPegInBalanceAfter, contractBalanceAfter] = await getBalances();

    expect(userPegInBalanceBefore.toString()).to.be.eq(
      userPegInBalanceAfter.toString()
    );
    expect(+contractBalanceAfter).to.be.eq(+contractBalanceBefore + msgValue.toNumber());
    
    // this is to wait for the quote to expire
    await utils.timeout((additionalSecondsToExpire + 2) * 1000);
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    await web3.eth.getBlock("latest")

    const refund = instance.refundPegOut(
      quote,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );

    await truffleAssertions.reverts(refund, "LBC046");
  });

  it("Should validate if the quote is expired blocks on refundPegOut", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    const getBalances = () =>
      Promise.all([
        instance.getBalance(liquidityProviderRskAddress),
        web3.eth.getBalance(instance.address),
      ]);

    const [userPegInBalanceBefore, contractBalanceBefore] = await getBalances();

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );

    quote.expireBlock = await web3.eth.getBlock("latest").then(block => block.number + 1);
    const msgValue = quote.value.add(quote.callFee);
    const pegOut = await instance.depositPegout(quote, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const [userPegInBalanceAfter, contractBalanceAfter] = await getBalances();

    expect(userPegInBalanceBefore.toString()).to.be.eq(
      userPegInBalanceAfter.toString()
    );
    expect(+contractBalanceAfter).to.be.eq(+contractBalanceBefore + msgValue.toNumber());

    const refund = instance.refundPegOut(
      quote,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );

    await truffleAssertions.reverts(refund, "LBC047");
  });

  it("should fail if provider is not registered for pegout on refundPegout", async () => {
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[4],
      web3.utils.toBN(1)
    );
    quote.transferConfirmations = 0;

    // configure mocked block on mockBridge
    const block = await web3.eth.getBlock("latest");
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 600).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    const nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeader(block.timestamp, firstHeader);
    await bridgeMockInstance.setHeader(
      block.timestamp + quote.depositConfirmations - 1,
      nHeader
    );

    await web3.eth.getBlock("latest");
    const refund = instance.refundPegOut(
      utils.asArray(quote),
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes,
      {
        from: accounts[4],
      }
    );
    await truffleAssertions.reverts(refund, "LBC001");
  });

  it("Should emit event when pegout is deposited", async () => {
    const quote = utils.getTestPegOutQuote(
        instance.address, //lbc address
        liquidityProviderRskAddress,
        accounts[2],
        1
      );
    const value = web3.utils.toBN("500") 
    const quoteHash = await instance.hashPegoutQuote(quote);
    const tx = await instance.depositPegout(
      quote,
      { value: value.toNumber() }
    );
    await truffleAssertions.eventEmitted(tx, "PegOutDeposit", {
      quoteHash: quoteHash,
      amount: value,
    });
    // check that stores quote
    const storedQuote = await instance.getRegisteredPegOutQuote(quoteHash)
    expect(storedQuote.lbcAddress).to.not.be.eq('0x0000000000000000000000000000000000000000')
  });

  it("Should not allow to deposit less than total required on pegout", async () => {
    const quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );

    const tx = instance.depositPegout(
      quote,
      { value: 500 }
    );

    await truffleAssertions.reverts(tx, "LBC063");
  });

  it("Should not allow to deposit pegout if quote expired", async () => {
    const quoteExpiredByBlocks = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );
    quoteExpiredByBlocks.expireBlock = await web3.eth.getBlock("latest").then(block => block.number - 1);
    const revertByBlocks = instance.depositPegout(
      quoteExpiredByBlocks,
      { value: 2000 }
    );

    await truffleAssertions.reverts(revertByBlocks, "LBC047");

    const quoteExpiredByTime = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );
    quoteExpiredByTime.expireDate = quoteExpiredByTime.agreementTimestamp;
    const revertByTime = instance.depositPegout(
      quoteExpiredByTime,
      { value: 2000 }
    );

    await truffleAssertions.reverts(revertByTime, "LBC046");
  });

  it("Should not allow to deposit the same quote twice", async () => {
    const quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );

    await instance.depositPegout(
      quote,
      { value: 1500 }
    );

    const tx = instance.depositPegout(
      quote,
      { value: 1500 }
    );

    await truffleAssertions.reverts(tx, "LBC028");
  });


  it("Should fail if provider is not registered", async () => {
    const quote = utils.getTestPegOutQuote(
        instance.address, //lbc address
        liquidityProviderRskAddress,
        accounts[2],
        web3.utils.toBN(3)
      );
    await instance.resign();
    await instance.withdrawPegoutCollateral();
    const tx = instance.depositPegout(quote, { value: web3.utils.toBN("500") });
    await truffleAssertions.reverts(tx, "LBC037");
  });

  it("Should refund user", async () => {
    const quoteValue = web3.utils.toBN("4");
    const penaltyValue = web3.utils.toBN("2");

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[1],
      quoteValue.toNumber()
    );
    quote.penaltyFee = penaltyValue.toNumber();

    // so its expired after deposit
    quote.expireBlock = await web3.eth.getBlock("latest").then(block => block.number + 1);
    quote.expireDate = Math.round(new Date().getTime() / 1000) + 1;

    const quoteHash = await instance.hashPegoutQuote(quote);

    const signature = await web3.eth.sign(
      quoteHash,
      liquidityProviderRskAddress
    );


    const depositAmount = web3.utils.toBN("5");
    const firstTx = await instance.depositPegout(quote, { value: depositAmount.toNumber() });

    await truffleAssertions.eventEmitted(firstTx, "PegOutDeposit", {
      quoteHash: quoteHash,
      amount: depositAmount,
    });
    // this is to wait for the quote to expire
    await utils.timeout(2000);
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    await web3.eth.getBlock("latest")

    const tx = await instance.refundUserPegOut(quote, signature);

    await truffleAssertions.eventEmitted(tx, "Penalized", {
      quoteHash: quoteHash,
      penalty:   penaltyValue,
      liquidityProvider: quote.lpRskAddress,
    });

    await truffleAssertions.eventEmitted(tx, "PegOutUserRefunded", {
      quoteHash: quoteHash,
      value: quoteValue,
      userAddress: quote.rskRefundAddress,
    });
  });

  it("Should validate if user had not deposited yet", async () => {
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[1],
      web3.utils.toBN(1)
    );

    // so its always expired
    quote.expireDate = quote.agreementTimestamp
    quote.expireBlock = 1

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));

    const signature = await web3.eth.sign(
      quoteHash,
      liquidityProviderRskAddress
    );

    const tx = instance.refundUserPegOut(utils.asArray(quote), signature);

    await truffleAssertions.reverts(tx, "LBC042");
  });
});
