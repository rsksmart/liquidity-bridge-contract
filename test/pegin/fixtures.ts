import hre, { ethers, upgrades } from "hardhat";
import { deployCollateralManagement } from "../utils/fixtures";
import { PegInContract } from "../../typechain-types";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { PEGIN_CONSTANTS, ZERO_ADDRESS } from "../utils/constants";
import { getTestPeginQuote } from "../utils/quotes";

export async function deployPegInContractFixture() {
  const deployResult = await deployCollateralManagement();
  const collateralManagement = deployResult.collateralManagement;
  const collateralManagementAddress = await collateralManagement.getAddress();
  const bridgeMock = await ethers.deployContract("BridgeMock");

  const initializationParams: Parameters<PegInContract["initialize"]> = [
    deployResult.owner.address,
    await bridgeMock.getAddress(),
    PEGIN_CONSTANTS.TEST_DUST_THRESHOLD,
    PEGIN_CONSTANTS.TEST_MIN_PEGIN,
    collateralManagementAddress,
    false,
    0,
    ZERO_ADDRESS,
  ];

  const libraries = await deployLibraries(
    hre.network.name,
    "Quotes",
    "BtcUtils",
    "SignatureValidator"
  );
  const PegInContract = await ethers.getContractFactory("PegInContract", {
    libraries: {
      Quotes: libraries.Quotes.address,
      BtcUtils: libraries.BtcUtils.address,
      SignatureValidator: libraries.SignatureValidator.address,
    },
  });

  const contract = await upgrades.deployProxy(
    PegInContract,
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

export async function callForUserExecutedFixture() {
  const deployResult = await deployPegInContractFixture();
  const { contract, fullLp, signers } = deployResult;
  const lbcAddress = await contract.getAddress();
  const user = signers[0];

  const quote = getTestPeginQuote({
    lbcAddress,
    liquidityProvider: fullLp,
    value: ethers.parseEther("1.2"),
    destinationAddress: user.address,
    refundAddress: user.address,
    productFeePercentage: 2,
  });
  const quoteHash = await contract
    .hashPegInQuote(quote)
    .then((result) => ethers.getBytes(result));
  const signature = await fullLp.signMessage(quoteHash);

  const tx = await contract
    .connect(fullLp)
    .callForUser(quote, { value: quote.value });
  const callForUserReceipt = await tx.wait();

  return {
    user,
    quote,
    liquidityProvider: fullLp,
    callForUserReceipt,
    quoteHash,
    signature,
    ...deployResult,
  };
}
