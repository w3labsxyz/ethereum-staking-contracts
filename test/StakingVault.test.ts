import { ethers } from "hardhat";
import { expect } from "chai";
import utils from "./utils";

const { createValidatorDeposits } = utils;

/**
 * Sets the balance of an address to a specific amount (in Ether)
 * Does not issue a transaction but uses an internal hardhat API
 *
 * @param address The address to set the balance of
 * @param amountInEth The amount to set the balance to (in Ether)
 *
 * @returns A promise that resolves when the balance has been updated
 *
 * @remarks
 * This function is intended for testing purposes only
 */
async function setBalance(address: string, amountInEth: number) {
  const amount = ethers.parseEther(amountInEth.toString());
  const amountInHex = `0x${amount.toString(16)}`;
  await ethers.provider.send("hardhat_setBalance", [address, amountInHex]);
}

/**
 * Updates the balance of an address by a relative amount (in Ether)
 * Does not issue a transaction but uses an internal hardhat API
 *
 * @param address The address to update the balance of
 * @param deltaInEth The amount to update the balance by (in Ether)
 *
 * @returns A promise that resolves when the balance has been updated
 *
 * @remarks
 * This function is intended for testing purposes only
 */
async function updateBalance(address: string, deltaInEth: number) {
  const deltaInWei = ethers.parseEther(deltaInEth.toString());

  const currentBalance = await ethers.provider.getBalance(address);
  const updatedBalance = currentBalance + deltaInWei;
  const amountInHex = `0x${updatedBalance.toString(16)}`;

  await ethers.provider.send("hardhat_setBalance", [address, amountInHex]);
}

describe.only("StakingVault", async () => {
  beforeEach(async function () {
    const [deployer, w3labs, staker, nobody, ethereumStakingContract] =
      await ethers.getSigners();

    this.staker = staker;
    this.deployer = deployer;
    this.w3labs = w3labs;
    this.nobody = nobody;
    this.ethereumStakingContract = ethereumStakingContract;

    this.ethereumStakingDepositContract = await ethers.deployContract(
      "DepositContract",
      [],
      {
        value: 0,
      },
    );

    this.stakingVaultContract = await ethers.deployContract("StakingVault", [
      staker.address,
      w3labs.address,
      this.ethereumStakingDepositContract.target,
      1000,
    ]);

    await this.stakingVaultContract.waitForDeployment();
  });

  it("has total shares", async function () {
    expect(await this.stakingVaultContract.feeBasisPoints()).to.equal(1000);
  });

  it("forbids fee withdrawal if there is none", async function () {
    await expect(
      this.stakingVaultContract.connect(this.staker).claim(),
    ).to.be.revertedWithCustomError(
      this.stakingVaultContract,
      "NoFundsToRelease",
    );
  });

  describe("deposit data registration", async () => {
    it("supports registration", async function () {
      const numberOfValidators = 1;
      const validatorDeposits = createValidatorDeposits(
        this.stakingVaultContract.target,
        numberOfValidators,
      );

      const res = this.stakingVaultContract
        .connect(this.w3labs)
        .registerDepositData(
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          validatorDeposits.pubkeys.map(() => 32000000000000000000n),
        );

      await expect(res).to.emit(
        this.stakingVaultContract,
        "DepositDataRegistered",
      );

      /*
      const validation = await this.stakingVaultContract
        .connect(this.w3labs)
        .getDepositData(0);

      console.log({ validation });
      */

      /* TODO: Implement deposit data verification
      const verification = await this.stakingVaultContract
        .connect(this.w3labs)
        .verifyValidatorDepositData(
          validation[0],
          validation[2],
          validation[1],
          validation[3],
        );

      console.log({ verification });
       */
    });
  });

  describe("depositing", async () => {
    it("allows to deposit via simple payment", async function () {
      const numberOfValidators = 1;
      const validatorDeposits = createValidatorDeposits(
        this.stakingVaultContract.target,
        numberOfValidators,
      );

      let res = this.stakingVaultContract
        .connect(this.w3labs)
        .registerDepositData(
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          validatorDeposits.pubkeys.map(() => 32000000000000000000n),
        );

      await expect(res).to.emit(
        this.stakingVaultContract,
        "DepositDataRegistered",
      );

      // Expect a deposit of an address other than the staker to be rejected
      await expect(
        this.w3labs.sendTransaction({
          to: this.stakingVaultContract.target,
          value: ethers.parseEther("1"),
        }),
      ).to.be.revertedWithCustomError(
        this.stakingVaultContract,
        "AccessControlUnauthorizedAccount",
      );

      // Expect a payment too small for the deposit data to be rejected
      await expect(
        this.staker.sendTransaction({
          to: this.stakingVaultContract.target,
          value: ethers.parseEther("1"),
        }),
      ).to.be.revertedWithCustomError(
        this.stakingVaultContract,
        "InvalidDepositAmount",
      );

      // Expect a payment too large for the deposit data to be rejected
      await expect(
        this.staker.sendTransaction({
          to: this.stakingVaultContract.target,
          value: ethers.parseEther("33"),
        }),
      ).to.be.revertedWithCustomError(
        this.stakingVaultContract,
        "InvalidDepositAmount",
      );

      // Expect a payment of the correct amount to be accepted
      res = this.staker.sendTransaction({
        to: this.stakingVaultContract.target,
        value: ethers.parseEther("32"),
      });
      await expect(res).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("-32"),
      );
      await expect(res).to.emit(
        this.ethereumStakingDepositContract,
        "DepositEvent",
      );
    });

    it("allows to submit multiple times and multiple deposits per transaction", async function () {
      const numberOfValidators = 10;
      const validatorDeposits = createValidatorDeposits(
        this.stakingVaultContract.target,
        numberOfValidators,
      );

      let res = this.stakingVaultContract
        .connect(this.w3labs)
        .registerDepositData(
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          validatorDeposits.pubkeys.map(() => 32000000000000000000n),
        );

      await expect(res).to.emit(
        this.stakingVaultContract,
        "DepositDataRegistered",
      );

      // Expect a payment of the correct amount to be accepted
      res = this.staker.sendTransaction({
        to: this.stakingVaultContract.target,
        value: ethers.parseEther("64"),
      });
      await expect(res).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("-64"),
      );
      await expect(res).to.emit(
        this.ethereumStakingDepositContract,
        "DepositEvent",
      );

      expect(await this.stakingVaultContract.stakedBalance()).to.equal(
        ethers.parseEther("64"),
      );

      // deposit data for 8 * 32 ETH are left, overpaying will be reverted
      await expect(
        this.staker.sendTransaction({
          to: this.stakingVaultContract.target,
          value: ethers.parseEther("320"),
        }),
      ).to.be.revertedWithCustomError(
        this.stakingVaultContract,
        "InvalidDepositAmount",
      );

      // Expect a payment of the correct amount to be accepted
      res = this.staker.sendTransaction({
        to: this.stakingVaultContract.target,
        value: ethers.parseEther("256"),
      });
      await expect(res).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("-256"),
      );
      await expect(res).to.emit(
        this.ethereumStakingDepositContract,
        "DepositEvent",
      );

      expect(await this.stakingVaultContract.stakedBalance()).to.equal(
        ethers.parseEther("320"),
      );
    });
  });

  describe("releasing rewards and pay fees", async () => {
    it("allows to withdraw accumulated fees and rewards", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.staker.address, 1);

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingVaultContract.target),
      ).to.equal(0);

      expect(await this.stakingVaultContract.claimedRewards()).to.equal(
        ethers.parseEther("0"),
      );

      // Staking rewards are accumulated in the contract
      await updateBalance(this.stakingVaultContract.target, 0.01);

      // Claiming releases rewards and fees
      let claim = this.stakingVaultContract.connect(this.staker).claim();
      // Releasable rewards amount to 90% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("0.009"),
      );
      // Fees amount to 10% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.w3labs,
        ethers.parseEther("0.001"),
      );

      // Expect to keep track of the amount released
      expect(await this.stakingVaultContract.claimedRewards()).to.equal(
        ethers.parseEther("0.009"),
      );
      expect(await this.stakingVaultContract.paidFees()).to.equal(
        ethers.parseEther("0.001"),
      );

      // New staking rewards are accumulated in the contract
      await updateBalance(this.stakingVaultContract.target, 0.1);

      // Claiming releases rewards and fees
      claim = this.stakingVaultContract.connect(this.staker).claim();
      // Releasable rewards amount to 90% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("0.09"),
      );
      // Fees amount to 10% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.w3labs,
        ethers.parseEther("0.01"),
      );

      // Expect to keep track of the amount released
      expect(await this.stakingVaultContract.claimedRewards()).to.equal(
        ethers.parseEther("0.099"),
      );
      expect(await this.stakingVaultContract.paidFees()).to.equal(
        ethers.parseEther("0.011"),
      );
    });

    it("keeps track of subsequently released stakes", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.staker.address, 33);

      const numberOfValidators = 1;
      const validatorDeposits = createValidatorDeposits(
        this.stakingVaultContract.target,
        numberOfValidators,
      );

      let res = this.stakingVaultContract
        .connect(this.w3labs)
        .registerDepositData(
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          validatorDeposits.pubkeys.map(() => 32000000000000000000n),
        );

      await expect(res).to.emit(
        this.stakingVaultContract,
        "DepositDataRegistered",
      );

      // Expect a payment of the correct amount to be accepted
      res = this.staker.sendTransaction({
        to: this.stakingVaultContract.target,
        value: ethers.parseEther("32"),
      });
      await expect(res).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("-32"),
      );
      await expect(res).to.changeEtherBalance(
        this.stakingVaultContract,
        ethers.parseEther("0"),
      );
      await expect(res).to.changeEtherBalance(
        this.ethereumStakingDepositContract,
        ethers.parseEther("32"),
      );
      await expect(res).to.emit(
        this.ethereumStakingDepositContract,
        "DepositEvent",
      );
      expect(await this.stakingVaultContract.stakedBalance()).to.equal(
        ethers.parseEther("32"),
      );

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingVaultContract.target),
      ).to.equal(0);
      expect(await this.stakingVaultContract.claimedRewards()).to.equal(
        ethers.parseEther("0"),
      );

      // Simulate accumulation of rewards for the first validator
      await updateBalance(this.stakingVaultContract.target, 0.01);

      // Claiming releases rewards and fees
      let claim = this.stakingVaultContract.connect(this.staker).claim();
      // Releasable rewards amount to 90% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.staker,
        ethers.parseEther("0.009"),
      );
      // Fees amount to 10% of the contract balance
      await expect(claim).to.changeEtherBalance(
        this.w3labs,
        ethers.parseEther("0.001"),
      );

      // Expect to keep track of the amount released
      expect(await this.stakingVaultContract.claimedRewards()).to.equal(
        ethers.parseEther("0.009"),
      );
      expect(await this.stakingVaultContract.paidFees()).to.equal(
        ethers.parseEther("0.001"),
      );

      // Exit the validator
      await this.stakingVaultContract
        .connect(this.staker)
        .exitValidator(validatorDeposits.pubkeys[0]);

      expect(await this.stakingVaultContract.stakedBalance()).to.equal(0);
      expect(await this.stakingVaultContract.payableFees()).to.equal(0);
      expect(await this.stakingVaultContract.claimableRewards()).to.equal(32);

      /*
      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingVaultContract.target, 32.02);

      // Add the validator 0x03^48
      await this.stakingVaultContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(2, 3));
      expect(
        await this.stakingVaultContract.numberOfActiveValidators(),
      ).to.equal(2);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 32 ETH initial stake)
      await expect(
        this.stakingVaultContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.005"));

      // Releasable rewards amount to 90% of the staking rewrads plus 32 ETH initial stake
      await expect(
        this.stakingVaultContract.connect(this.staker).release(),
      ).to.changeEtherBalance(this.staker, ethers.parseEther("32.045"));

      // Exit the validator 0x02^48
      await this.stakingVaultContract
        .connect(this.staker)
        .exitValidator(validatorPublicKeys[1]);
      expect(
        await this.stakingVaultContract.numberOfActiveValidators(),
      ).to.equal(1);
      // Exit the validator 0x03^48
      await this.stakingVaultContract
        .connect(this.staker)
        .exitValidator(validatorPublicKeys[2]);
      expect(
        await this.stakingVaultContract.numberOfActiveValidators(),
      ).to.equal(0);

      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingVaultContract.target, 32.02);
      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingVaultContract.target, 32.03);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 64 ETH released stake)
      await expect(
        this.stakingVaultContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.005"));

      // Releasable rewards amount to 90% of the staking rewrads plus 32 ETH initial stake
      await expect(
        this.stakingVaultContract.connect(this.staker).release(),
      ).to.changeEtherBalance(this.staker, ethers.parseEther("64.045"));
       */
    });
  });
});
