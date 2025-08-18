import hre, { upgrades, ethers } from "hardhat";
import { PEGOUT_CONSTANTS, ZERO_ADDRESS } from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { PegOutContract } from "../../typechain-types";
import { getTestPegoutQuote, totalValue } from "../utils/quotes";
import { getBytes } from "ethers";
import { deployCollateralManagement } from "../utils/fixtures";

export async function deployPegOutContractFixture() {
  const deployResult = await deployCollateralManagement();
  const collateralManagement = deployResult.collateralManagement;
  const collateralManagementAddress = await collateralManagement.getAddress();
  const bridgeMock = await ethers.deployContract("BridgeMock");

  const initializationParams: Parameters<PegOutContract["initialize"]> = [
    deployResult.owner.address,
    await bridgeMock.getAddress(),
    PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD,
    collateralManagementAddress,
    false,
    PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME,
    0,
    ZERO_ADDRESS,
  ];

  const libraries = await deployLibraries(
    hre.network.name,
    "Quotes",
    "BtcUtils",
    "SignatureValidator"
  );
  const PegOutContract = await ethers.getContractFactory("PegOutContract", {
    libraries: {
      Quotes: libraries.Quotes.address,
      BtcUtils: libraries.BtcUtils.address,
      SignatureValidator: libraries.SignatureValidator.address,
    },
  });

  const contract = await upgrades.deployProxy(
    PegOutContract,
    initializationParams,
    {
      unsafeAllow: ["external-library-linking"],
    }
  );
  await collateralManagement
    .connect(deployResult.owner)
    .grantRole(
      await collateralManagement.COLLATERAL_SLASHER(),
      await contract.getAddress()
    );
  return { contract, bridgeMock, initializationParams, ...deployResult };
}

export async function paidPegOutFixture() {
  const deployResult = await deployPegOutContractFixture();
  const { signers, contract, pegOutLp } = deployResult;
  const user = signers.pop();
  if (!user) throw new Error("user can't be undefined");
  const quote = getTestPegoutQuote({
    lbcAddress: await contract.getAddress(),
    liquidityProvider: pegOutLp,
    refundAddress: user.address,
    value: ethers.parseEther("1.23"),
  });
  const quoteHash = await contract.hashPegOutQuote(quote);
  const signature = await pegOutLp.signMessage(getBytes(quoteHash));
  const depositTx = await contract
    .connect(user)
    .depositPegOut(quote, signature, { value: totalValue(quote) });
  const depositReceipt = await depositTx.wait();

  return {
    user,
    usedLp: pegOutLp,
    quote,
    quoteHash,
    depositTx,
    depositReceipt,
    ...deployResult,
  };
}
