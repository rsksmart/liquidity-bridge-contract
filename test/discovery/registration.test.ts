import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import {
  deployDiscoveryFixture,
  deployDiscoveryWithProvidersFixture,
} from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery registration", () => {
  it("registers providers and increments lastProviderId", async () => {
    const { discovery, signers, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const [lp1, lp2, lp3] = signers.slice(-3);

    const tx1 = await discovery
      .connect(lp1)
      .register("LP1", "http://localhost/api1", true, ProviderType.Both, {
        value: MIN_COLLATERAL * 2n,
      });
    await expect(tx1).to.emit(discovery, "Register");

    const tx2 = await discovery
      .connect(lp2)
      .register("LP2", "http://localhost/api2", true, ProviderType.PegIn, {
        value: MIN_COLLATERAL,
      });
    await expect(tx2).to.emit(discovery, "Register");

    const tx3 = await discovery
      .connect(lp3)
      .register("LP3", "http://localhost/api3", true, ProviderType.PegOut, {
        value: MIN_COLLATERAL,
      });
    await expect(tx3).to.emit(discovery, "Register");

    const lastId = await discovery.getProvidersId();
    expect(lastId).to.equal(3n);
  });

  it("reverts on invalid registration data (empty name/url)", async () => {
    const { discovery, signers, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const lp = signers.at(-1)!;

    await expect(
      discovery
        .connect(lp)
        .register("", "http://localhost/api", true, ProviderType.PegIn, {
          value: MIN_COLLATERAL,
        })
    ).to.be.revertedWithCustomError(discovery, "InvalidProviderData");

    await expect(
      discovery.connect(lp).register("LP", "", true, ProviderType.PegIn, {
        value: MIN_COLLATERAL,
      })
    ).to.be.revertedWithCustomError(discovery, "InvalidProviderData");
  });

  it("reverts on insufficient collateral depending on provider type", async () => {
    const { discovery, signers, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const [lpBoth, lpIn, lpOut] = signers.slice(-3);

    await expect(
      discovery
        .connect(lpBoth)
        .register("LPB", "url", true, ProviderType.Both, {
          value: MIN_COLLATERAL, // needs 2x
        })
    ).to.be.revertedWithCustomError(discovery, "InsufficientCollateral");

    await expect(
      discovery.connect(lpIn).register("LPI", "url", true, ProviderType.PegIn, {
        value: MIN_COLLATERAL - 1n,
      })
    ).to.be.revertedWithCustomError(discovery, "InsufficientCollateral");

    await expect(
      discovery
        .connect(lpOut)
        .register("LPO", "url", true, ProviderType.PegOut, {
          value: MIN_COLLATERAL - 1n,
        })
    ).to.be.revertedWithCustomError(discovery, "InsufficientCollateral");
  });

  it("returns the last provider id after pre-registered providers", async () => {
    const { discovery } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const lastId = await discovery.getProvidersId();
    expect(lastId).to.equal(3n);
  });
});

describe("FlyoverDiscovery registration edge cases", () => {
  it("reverts when providerType is invalid", async () => {
    const { discovery, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const RegisterCaller = await (
      await import("hardhat")
    ).ethers.getContractFactory("RegisterCaller");
    const caller = await RegisterCaller.deploy();
    await caller.waitForDeployment();
    // Note: With the current function signature (enum parameter), the ABI decoder
    // reverts with panic 0x21 for values outside the enum before the function body
    // executes, so the contract's InvalidProviderType custom error cannot be reached.
    // To assert the custom error instead, the contract would need to accept a raw
    // uint8 and validate inside before casting to the enum.
    await expect(
      caller.callRegisterWithTypeUint(
        await discovery.getAddress(),
        "N",
        "U",
        true,
        999,
        { value: MIN_COLLATERAL }
      )
    ).to.be.revertedWithPanic(0x21);
  });

  it("prevents multiple registrations by the same EOA", async () => {
    const { discovery, signers, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const lp = signers.at(-1)!;
    await discovery.connect(lp).register("N1", "U1", true, ProviderType.PegIn, {
      value: MIN_COLLATERAL,
    });

    // Second registration by the same EOA should fail
    await expect(
      discovery.connect(lp).register("N2", "U2", true, ProviderType.PegOut, {
        value: MIN_COLLATERAL,
      })
    ).to.be.revertedWithCustomError(discovery, "AlreadyRegistered");

    const providers = await discovery.getProviders();
    expect(providers.length).to.equal(1);
    expect(providers[0].providerAddress).to.equal(lp.address);
  });
});
