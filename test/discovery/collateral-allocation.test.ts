import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployDiscoveryFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery collateral allocation", () => {
  it("correctly allocates collateral for ProviderType.PegIn", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-1)!;

    const collateralAmount = MIN_COLLATERAL;
    await discovery
      .connect(lp)
      .register("PegIn LP", "http://localhost/api", true, ProviderType.PegIn, {
        value: collateralAmount,
      });

    // Verify collateral allocation in CollateralManagement contract
    expect(await collateralManagement.getPegInCollateral(lp.address)).to.equal(
      collateralAmount
    );
    expect(await collateralManagement.getPegOutCollateral(lp.address)).to.equal(
      0n
    );
  });

  it("correctly allocates collateral for ProviderType.PegOut", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-2)!;

    const collateralAmount = MIN_COLLATERAL;
    await discovery
      .connect(lp)
      .register(
        "PegOut LP",
        "http://localhost/api",
        true,
        ProviderType.PegOut,
        {
          value: collateralAmount,
        }
      );

    // Verify collateral allocation in CollateralManagement contract
    expect(await collateralManagement.getPegInCollateral(lp.address)).to.equal(
      0n
    );
    expect(await collateralManagement.getPegOutCollateral(lp.address)).to.equal(
      collateralAmount
    );
  });

  it("correctly allocates collateral for ProviderType.Both with even amount", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-3)!;

    const collateralAmount = MIN_COLLATERAL * 2n; // Even amount
    await discovery
      .connect(lp)
      .register("Both LP", "http://localhost/api", true, ProviderType.Both, {
        value: collateralAmount,
      });

    // Verify collateral allocation in CollateralManagement contract
    const expectedHalf = collateralAmount / 2n;
    expect(await collateralManagement.getPegInCollateral(lp.address)).to.equal(
      expectedHalf
    );
    expect(await collateralManagement.getPegOutCollateral(lp.address)).to.equal(
      expectedHalf
    );
  });

  it("correctly allocates collateral for ProviderType.Both with odd amount", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-4)!;

    const collateralAmount = MIN_COLLATERAL * 2n + 1n; // Odd amount
    await discovery
      .connect(lp)
      .register(
        "Both LP Odd",
        "http://localhost/api",
        true,
        ProviderType.Both,
        {
          value: collateralAmount,
        }
      );

    // Verify collateral allocation in CollateralManagement contract
    const halfAmount = collateralAmount / 2n;
    const remainder = collateralAmount % 2n;
    const expectedPegIn = halfAmount + remainder; // Should get the extra 1
    const expectedPegOut = halfAmount;

    expect(await collateralManagement.getPegInCollateral(lp.address)).to.equal(
      expectedPegIn
    );
    expect(await collateralManagement.getPegOutCollateral(lp.address)).to.equal(
      expectedPegOut
    );

    // Verify total allocation equals the original amount
    const totalAllocated =
      (await collateralManagement.getPegInCollateral(lp.address)) +
      (await collateralManagement.getPegOutCollateral(lp.address));
    expect(totalAllocated).to.equal(collateralAmount);
  });

  it("handles edge case with minimum odd amount for ProviderType.Both", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-5)!;

    // Test with minimum required amount + 1 (odd)
    const collateralAmount = MIN_COLLATERAL * 2n + 1n;
    await discovery
      .connect(lp)
      .register(
        "Both LP Min Odd",
        "http://localhost/api",
        true,
        ProviderType.Both,
        {
          value: collateralAmount,
        }
      );

    // Verify the allocation
    const halfAmount = collateralAmount / 2n;
    expect(await collateralManagement.getPegInCollateral(lp.address)).to.equal(
      halfAmount + 1n
    );
    expect(await collateralManagement.getPegOutCollateral(lp.address)).to.equal(
      halfAmount
    );
  });

  it("verifies collateral is actually transferred to CollateralManagement contract", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-6)!;

    // Get initial balance of CollateralManagement contract
    const initialBalance = await ethers.provider.getBalance(
      await collateralManagement.getAddress()
    );

    const collateralAmount = MIN_COLLATERAL;
    await discovery
      .connect(lp)
      .register("Test LP", "http://localhost/api", true, ProviderType.PegIn, {
        value: collateralAmount,
      });

    // Verify the CollateralManagement contract received the funds
    const finalBalance = await ethers.provider.getBalance(
      await collateralManagement.getAddress()
    );
    expect(finalBalance - initialBalance).to.equal(collateralAmount);
  });

  it("verifies total collateral allocation matches sent amount for all provider types", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const [lp1, lp2, lp3] = signers.slice(-3);

    // Test PegIn
    const pegInAmount = MIN_COLLATERAL;
    await discovery
      .connect(lp1)
      .register("PegIn LP", "http://localhost/api", true, ProviderType.PegIn, {
        value: pegInAmount,
      });

    let totalAllocated =
      (await collateralManagement.getPegInCollateral(lp1.address)) +
      (await collateralManagement.getPegOutCollateral(lp1.address));
    expect(totalAllocated).to.equal(pegInAmount);

    // Test PegOut
    const pegOutAmount = MIN_COLLATERAL;
    await discovery
      .connect(lp2)
      .register(
        "PegOut LP",
        "http://localhost/api",
        true,
        ProviderType.PegOut,
        {
          value: pegOutAmount,
        }
      );

    totalAllocated =
      (await collateralManagement.getPegInCollateral(lp2.address)) +
      (await collateralManagement.getPegOutCollateral(lp2.address));
    expect(totalAllocated).to.equal(pegOutAmount);

    // Test Both with odd amount
    const bothAmount = MIN_COLLATERAL * 2n + 3n; // Odd amount
    await discovery
      .connect(lp3)
      .register("Both LP", "http://localhost/api", true, ProviderType.Both, {
        value: bothAmount,
      });

    totalAllocated =
      (await collateralManagement.getPegInCollateral(lp3.address)) +
      (await collateralManagement.getPegOutCollateral(lp3.address));
    expect(totalAllocated).to.equal(bothAmount);
  });

  it("emits correct events for collateral allocation", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-7)!;

    const collateralAmount = MIN_COLLATERAL;
    const tx = await discovery
      .connect(lp)
      .register("Event LP", "http://localhost/api", true, ProviderType.PegIn, {
        value: collateralAmount,
      });

    // Verify the Register event
    await expect(tx)
      .to.emit(discovery, "Register")
      .withArgs(1n, lp.address, collateralAmount);

    // Verify the PegInCollateralAdded event
    await expect(tx)
      .to.emit(collateralManagement, "PegInCollateralAdded")
      .withArgs(lp.address, collateralAmount);
  });

  it("emits correct events for ProviderType.Both allocation", async () => {
    const { discovery, collateralManagement, signers, MIN_COLLATERAL } =
      await loadFixture(deployDiscoveryFixture);
    const lp = signers.at(-8)!;

    const collateralAmount = MIN_COLLATERAL * 2n + 1n; // Odd amount
    const tx = await discovery
      .connect(lp)
      .register(
        "Both Event LP",
        "http://localhost/api",
        true,
        ProviderType.Both,
        {
          value: collateralAmount,
        }
      );

    // Verify the Register event
    await expect(tx)
      .to.emit(discovery, "Register")
      .withArgs(1n, lp.address, collateralAmount);

    // Verify both collateral events
    const halfAmount = collateralAmount / 2n;
    const remainder = collateralAmount % 2n;

    await expect(tx)
      .to.emit(collateralManagement, "PegInCollateralAdded")
      .withArgs(lp.address, halfAmount + remainder);

    await expect(tx)
      .to.emit(collateralManagement, "PegOutCollateralAdded")
      .withArgs(lp.address, halfAmount);
  });
});
