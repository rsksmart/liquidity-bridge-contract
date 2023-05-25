const LiquidityBridgeContract = artifacts.require("LiquidityBridgeContract");
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require("Mock");
const truffleAssert = require("truffle-assertions");
const utils = require("../test/utils/index");

const chai = require("chai");
const truffleAssertions = require("truffle-assertions");
const BN = web3.utils.BN;
const chaiBN = require("chai-bn")(BN);
chai.use(chaiBN);
const expect = chai.expect;

contract("LiquidityBridgeContract", async (accounts) => {
  let instance;
  let bridgeMockInstance;
  const liquidityProviderRskAddress = accounts[0];

  before(async () => {
    const proxy = await LiquidityBridgeContract.deployed();
    instance = await LiquidityBridgeContract.at(proxy.address);
    bridgeMockInstance = await BridgeMock.deployed();
    const mock = await Mock.deployed();
  });

  beforeEach(async () => {
    await utils.ensureLiquidityProviderAvailable(
      instance,
      liquidityProviderRskAddress,
      utils.LP_COLLATERAL
    );
  });

  it("should not allow attacker to steal funds", async () => {
    // The attacker controls a liquidity provider and also a destination address
    // Note that these could be the same address, separated for clarity
    let attackingLP = accounts[7];
    let attackerCollateral = web3.utils.toWei("10");
    await instance.register.call(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      'both',
      {
        value: attackerCollateral,
        from: attackingLP,
      }
    );

    let goodLP = accounts[8];
    let goodProviderCollateral = web3.utils.toWei("30");
    await instance.register.call(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      'both',
      {
        value: goodProviderCollateral,
        from: goodLP,
      }
    );

    let attackerDestAddress = accounts[9];

    // Add funds from an innocent liquidity provider, note again this could be
    // done by an attacker
    // The quote value in wei should be bigger than 2**63-1. 10 RBTC is a good approximation.
    let quoteValue = web3.utils.numberToHex(web3.utils.toWei("10"));
    // Let's create the evil quote.
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let userBtcRefundAddress = "0x000000000000000000000000000000000000000000";
    let liquidityProviderBtcAddress =
      "0x000000000000000000000000000000000000000000";
    let rskRefundAddress = attackerDestAddress;
    let fedBtcAddress = "0x0000000000000000000000000000000000000000";
    let liquidityProviderRskAddress = attackingLP;
    let data = "0x00";
    let callFee = web3.utils.toBN(1);
    let gasLimit = 30000;
    let nonce = 1;
    let lbcAddress = instance.address;
    let agreementTime = 1661788988;
    let timeForDeposit = 600;
    let callTime = 600;
    let depositConfirmations = 10;
    let penaltyFee = web3.utils.toBN(0);
    let callOnRegister = true;
    let quote = [
      fedBtcAddress,
      lbcAddress,
      liquidityProviderRskAddress,
      userBtcRefundAddress,
      rskRefundAddress,
      liquidityProviderBtcAddress,
      callFee,
      penaltyFee,
      attackerDestAddress,
      data,
      gasLimit,
      nonce,
      quoteValue,
      agreementTime,
      timeForDeposit,
      callTime,
      depositConfirmations,
      callOnRegister,
    ];
    // Let's now register our quote in the bridge... note that the
    // value is only a hundred wei
    let transferredInBTC = 100;
    let quoteHash = await instance.hashQuote(quote);
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(
      height + depositConfirmations - 1,
      nHeader
    );
    await bridgeMockInstance.setPegin(quoteHash, { value: transferredInBTC });

    // Register the peg in with the evil quote
    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        quote,
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC057"
    );
  });

  it("should pay with insufficient deposit that is not lower than (agreed amount - delta)", async () => {
    let val = web3.utils.toBN(1000000);
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let userBtcRefundAddress = "0x000000000000000000000000000000000000000000";
    let liquidityProviderBtcAddress =
      "0x000000000000000000000000000000000000000000";
    let rskRefundAddress = accounts[2];
    let destAddr = accounts[1];
    let initialUserBalance = await web3.eth.getBalance(destAddr);
    let fedBtcAddress = "0x0000000000000000000000000000000000000000";
    let liquidityProviderRskAddress = accounts[0];
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(instance.address);
    let data = "0x00";
    let callFee = 1;
    let gasLimit = 150000;
    let nonce = 0;
    let delta = web3.utils
      .toBN(val)
      .add(web3.utils.toBN(callFee))
      .div(web3.utils.toBN(10000));
    let peginAmount = web3.utils
      .toBN(val)
      .add(web3.utils.toBN(callFee))
      .sub(delta);
    let lbcAddress = instance.address;
    let agreementTime = 1661788988;
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
      callOnRegister,
    ];
    let quoteHash = await instance.hashQuote(quote);
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 600).substring(2)
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
      height + depositConfirmations - 1,
      nHeader
    );

    let initialLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    await instance.callForUser(quote, { value: val });

    let currentLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );

    expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

    let amount = await instance.registerPegIn.call(
      quote,
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    await instance.registerPegIn(
      quote,
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

    let usrBal = web3.utils
      .toBN(finalUserBalance)
      .sub(web3.utils.toBN(initialUserBalance));
    let lbcBal = web3.utils
      .toBN(finalLBCBalance)
      .sub(web3.utils.toBN(initialLBCBalance));
    let lpBal = web3.utils
      .toBN(finalLPBalance)
      .sub(web3.utils.toBN(initialLPBalance));
    expect(peginAmount).to.be.a.bignumber.eq(amount);
    expect(usrBal).to.be.a.bignumber.eq(val);
    expect(lbcBal).to.be.a.bignumber.eq(peginAmount);
    expect(lpBal).to.be.a.bignumber.eq(peginAmount);
    expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
  });

  it("should revert on insufficient deposit", async () => {
    let val = web3.utils.toBN(1000000);
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x201";
    let height = 10;
    let userBtcRefundAddress = "0x000000000000000000000000000000000000000000";
    let liquidityProviderBtcAddress =
      "0x000000000000000000000000000000000000000000";
    let rskRefundAddress = accounts[2];
    let destAddr = accounts[1];
    let fedBtcAddress = "0x0000000000000000000000000000000000000000";
    let liquidityProviderRskAddress = accounts[0];
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], [
      "100100001110010",
    ]);
    let callFee = 1;
    let gasLimit = 150000;
    let nonce = 1;
    let delta = web3.utils
      .toBN(val)
      .add(web3.utils.toBN(callFee))
      .div(web3.utils.toBN(10000));
    let peginAmount = web3.utils
      .toBN(val)
      .add(web3.utils.toBN(callFee))
      .sub(delta)
      .sub(web3.utils.toBN(1));
    let lbcAddress = instance.address;
    let agreementTime = 1661788988;
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
      callOnRegister,
    ];
    let quoteHash = await instance.hashQuote(quote);
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(agreementTime + 600).substring(2)
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
      height + depositConfirmations - 1,
      nHeader
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        quote,
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC057"
    );
  });

  it("should validate reward percentage arg in initialize", async () => {
    let instance = await LiquidityBridgeContract.new();
    const MAX_QUOTE_VALUE = web3.utils.toBN("1000000000000000000")
    await instance.initialize(bridgeMockInstance.address, 1, 1, 0, 1, 1, MAX_QUOTE_VALUE);
    instance = await LiquidityBridgeContract.new();
    await instance.initialize(bridgeMockInstance.address, 1, 1, 0, 1, 1, MAX_QUOTE_VALUE);
    instance = await LiquidityBridgeContract.new();
    await instance.initialize(bridgeMockInstance.address, 1, 1, 1, 1, 1, MAX_QUOTE_VALUE);
    instance = await LiquidityBridgeContract.new();
    await instance.initialize(bridgeMockInstance.address, 1, 1, 99, 1, 1, MAX_QUOTE_VALUE);
    instance = await LiquidityBridgeContract.new();
    await instance.initialize(bridgeMockInstance.address, 1, 1, 100, 1, 1, MAX_QUOTE_VALUE);
    await truffleAssert.fails(
      instance.initialize(bridgeMockInstance.address, 1, 1, 100, 1, 1, MAX_QUOTE_VALUE)
    );
    instance = await LiquidityBridgeContract.new();
    await truffleAssert.fails(
      instance.initialize(bridgeMockInstance.address, 1, 1, 101, 1, 1, MAX_QUOTE_VALUE)
    );
  });

  it("should extract timestamp from btc block header", async () => {
    const btcHeader =
      "0x0080cf2a0857bdec9d66f5feb52d00d5061ff02a904112d9b0cd1ac401000000000000003d2d2b5733c820a1f07ce6e0acd2ea47f27016b49ccb405b1e3e5786f8ae962e3ce30c63bc292d1919856362";

    let timestamp = await instance.getBtcBlockTimestamp(btcHeader);
    expect(timestamp).to.be.a.bignumber.eq(web3.utils.toBN(1661788988));

    const btcHeader2 = "0x" + "00".repeat(68) + "12345678" + "00".repeat(8);

    let timestamp2 = await instance.getBtcBlockTimestamp(btcHeader2);
    expect(timestamp2).to.be.a.bignumber.eq(web3.utils.toBN("0x78563412"));
  });

  it("should fail to extract timestamp from btc block header with invalid length", async () => {
    const btcHeaderEmpty = "0x";
    const btcHeader79 = "0x" + "00".repeat(79);
    const btcHeader81 = "0x" + "00".repeat(81);

    await truffleAssertions.reverts(
      instance.getBtcBlockTimestamp(btcHeaderEmpty),
      "LBC061"
    );
    await truffleAssertions.reverts(
      instance.getBtcBlockTimestamp(btcHeader79),
      "LBC061"
    );
    await truffleAssertions.reverts(
      instance.getBtcBlockTimestamp(btcHeader81),
      "LBC061"
    );
  });
});
