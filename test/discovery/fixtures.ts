import { upgrades, ethers } from "hardhat";
import { ProviderType } from "../utils/constants";

export async function deployDiscoveryFixture() {
  const CollateralManagement = await ethers.getContractFactory(
    "CollateralManagementContract"
  );
  const FlyoverDiscovery = await ethers.getContractFactory("FlyoverDiscovery");

  const signers = await ethers.getSigners();
  const lastSigner = signers.pop();
  if (!lastSigner) throw new Error("owner can't be undefined");
  const owner = lastSigner;

  const MIN_COLLATERAL = ethers.parseEther("0.6");
  const INITIAL_DELAY = 500n;
  const RESIGN_DELAY = 500n;
  const REWARD_PERCENTAGE = 50n; // 50% reward for punishers

  const collateralManagement = await upgrades.deployProxy(
    CollateralManagement,
    [
      owner.address,
      INITIAL_DELAY,
      MIN_COLLATERAL,
      RESIGN_DELAY,
      REWARD_PERCENTAGE,
    ]
  );

  const discovery = await upgrades.deployProxy(FlyoverDiscovery, [
    owner.address,
    INITIAL_DELAY,
    await collateralManagement.getAddress(),
  ]);

  // Allow owner to add collateral directly for test setup
  await collateralManagement
    .connect(owner)
    .grantRole(await collateralManagement.COLLATERAL_ADDER(), owner.address);

  // Grant COLLATERAL_ADDER role to FlyoverDiscovery contract
  await collateralManagement
    .connect(owner)
    .grantRole(
      await collateralManagement.COLLATERAL_ADDER(),
      await discovery.getAddress()
    );

  return {
    discovery,
    collateralManagement,
    owner,
    signers,
    MIN_COLLATERAL,
  };
}

export async function deployDiscoveryWithProvidersFixture() {
  const { discovery, collateralManagement, owner, signers, MIN_COLLATERAL } =
    await deployDiscoveryFixture();

  const pegInLp = signers.pop();
  const pegOutLp = signers.pop();
  const fullLp = signers.pop();
  if (!pegInLp || !pegOutLp || !fullLp)
    throw new Error("LP can't be undefined");

  // Register providers (Discovery now handles collateral addition automatically)
  await discovery
    .connect(pegInLp)
    .register("Pegin Provider", "lp1.com", true, ProviderType.PegIn, {
      value: MIN_COLLATERAL,
    });
  await discovery
    .connect(pegOutLp)
    .register("PegOut Provider", "lp2.com", true, ProviderType.PegOut, {
      value: MIN_COLLATERAL,
    });
  await discovery
    .connect(fullLp)
    .register("Full Provider", "lp3.com", true, ProviderType.Both, {
      value: MIN_COLLATERAL * 2n,
    });

  return {
    discovery,
    collateralManagement,
    owner,
    pegInLp,
    pegOutLp,
    fullLp,
    signers,
    MIN_COLLATERAL,
  };
}
