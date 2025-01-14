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

describe("StakingRewards", async () => {
  describe("contract deployment", async () => {
    it("rejects fees higher than 100%", async () => {
      const [depositor, feeRecipient, rewardsRecipient] =
        await ethers.getSigners();

      try {
        await ethers.deployContract(
          "StakingRewards",
          [depositor, feeRecipient, rewardsRecipient, 10001],
          { value: 0 },
        );
        expect.fail("Contract deployed successfully, but was expected to fail");
      } catch (error: unknown) {
        expect(error.message).to.eq(
          "VM Exception while processing transaction: reverted with custom error 'InvalidFeeBasisPoints(10001)'",
        );
      }
    });

    it("rejects fees between 0% and 100%", async () => {
      const [depositor, feeRecipient, rewardsRecipient] =
        await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "StakingRewards",
          [depositor, feeRecipient, rewardsRecipient, 100],
          { value: 0 },
        ),
      ).not.to.be.reverted;
    });
  });

  describe("after deployment", async () => {
    beforeEach(async function () {
      const [deployer, w3labs, customer, nobody, ethereumStakingContract] =
        await ethers.getSigners();

      this.customer = customer;
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

      this.stakingRewardsContract = await ethers.deployContract(
        "StakingRewards",
        [deployer.address, w3labs.address, customer.address, 1000],
      );

      await this.stakingRewardsContract.waitForDeployment();
    });

    it("has total shares", async function () {
      expect(await this.stakingRewardsContract.feeBasisPoints()).to.equal(1000);
    });

    it("forbids fee withdrawal if there is none", async function () {
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "NoFundsToRelease",
      );
    });

    describe("access control", async () => {
      it("forbids deployer to withdraw fees", async function () {
        await expect(
          this.stakingRewardsContract.connect(this.deployer).release(),
        ).to.be.revertedWithCustomError(
          this.stakingRewardsContract,
          "SenderNotPermittedToReleaseFunds",
        );
      });

      it("forbids random addresses to withdraw fees", async function () {
        await expect(
          this.stakingRewardsContract.connect(this.nobody).release(),
        ).to.be.revertedWithCustomError(
          this.stakingRewardsContract,
          "SenderNotPermittedToReleaseFunds",
        );
      });

      it("forbids deployer to withdraw rewards", async function () {
        await expect(
          this.stakingRewardsContract.connect(this.deployer).release(),
        ).to.be.revertedWithCustomError(
          this.stakingRewardsContract,
          "SenderNotPermittedToReleaseFunds",
        );
      });

      it("forbids random addresses to withdraw rewards", async function () {
        await expect(
          this.stakingRewardsContract.connect(this.nobody).release(),
        ).to.be.revertedWithCustomError(
          this.stakingRewardsContract,
          "SenderNotPermittedToReleaseFunds",
        );
      });

      it("forbids fee recipient to add validators", async function () {
        const DEPOSITOR_ROLE =
          await this.stakingRewardsContract.DEPOSITOR_ROLE();

        await expect(
          this.stakingRewardsContract
            .connect(this.w3labs)
            .activateValidators([]),
        ).to.be.revertedWith(
          `AccessControl: account ${this.w3labs.address.toLowerCase()} is missing role ${DEPOSITOR_ROLE}`,
        );
      });

      it("forbids rewards recipient to add validators", async function () {
        const DEPOSITOR_ROLE =
          await this.stakingRewardsContract.DEPOSITOR_ROLE();

        await expect(
          this.stakingRewardsContract
            .connect(this.customer)
            .activateValidators([]),
        ).to.be.revertedWith(
          `AccessControl: account ${this.customer.address.toLowerCase()} is missing role ${DEPOSITOR_ROLE}`,
        );
      });

      it("forbids random addresses to add validators", async function () {
        const DEPOSITOR_ROLE =
          await this.stakingRewardsContract.DEPOSITOR_ROLE();

        await expect(
          this.stakingRewardsContract
            .connect(this.nobody)
            .activateValidators([]),
        ).to.be.revertedWith(
          `AccessControl: account ${this.nobody.address.toLowerCase()} is missing role ${DEPOSITOR_ROLE}`,
        );
      });
    });

    it("validates validator public keys", async function () {
      const invalidPublicKey = `0x${"00".repeat(47)}`;
      await expect(
        this.stakingRewardsContract
          .connect(this.deployer)
          .activateValidators([invalidPublicKey]),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "PublicKeyLengthMismatch",
      );
    });

    it("can not add the same validator twice", async function () {
      const validatorPublicKey = `0x${"01".repeat(48)}`;
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators([validatorPublicKey]);

      await expect(
        this.stakingRewardsContract
          .connect(this.deployer)
          .activateValidators([validatorPublicKey]),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "ValidatorAlreadyActive",
      );
    });

    it("emits `ValidatorsActivated` upon activation of validators and `ValidatorExited` upon successful exit", async function () {
      const validatorPublicKey = `0x${"01".repeat(48)}`;

      let res = await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators([validatorPublicKey]);

      await expect(res)
        .to.emit(this.stakingRewardsContract, "ValidatorsActivated")
        .withArgs([validatorPublicKey]);

      res = await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKey);

      await expect(res)
        .to.emit(this.stakingRewardsContract, "ValidatorExited")
        .withArgs(validatorPublicKey);
    });

    it("prevents exiting a validator that has not been added", async function () {
      const validatorPublicKey = `0x${"01".repeat(48)}`;
      await expect(
        this.stakingRewardsContract
          .connect(this.customer)
          .exitValidator(validatorPublicKey),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "ValidatorNotActive",
      );
    });

    it("prevents exiting a validator that has already exited", async function () {
      const validatorPublicKey = `0x${"01".repeat(48)}`;
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators([validatorPublicKey]);
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKey);
      await expect(
        this.stakingRewardsContract
          .connect(this.customer)
          .exitValidator(validatorPublicKey),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "ValidatorNotActive",
      );
    });

    it("prevents adding an empty set of validators", async function () {
      await expect(
        this.stakingRewardsContract
          .connect(this.deployer)
          .activateValidators([]),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "NoValidatorsToActivate",
      );
    });

    it("prevents (valid!) withdrawal of fees until validator exit has been finished", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.customer.address, 1);

      const validatorPublicKeys = [`0x${"01".repeat(48)}`];

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(0);
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0"),
      );

      // Add the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys);

      // Simulate accumulation of rewards for the first validator
      await updateBalance(this.stakingRewardsContract.target, 0.01);

      // Exit the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[0]);

      // Try to withdraw fees after exit but prior to validator sweep
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "NoFundsToRelease",
      );

      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingRewardsContract.target, 32.01);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 32 ETH initial stake)
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.002"));
    });

    it("withdrawal of fees doesn't underflow if subsequent validator exit has been finished", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.customer.address, 1);

      const validatorPublicKeys = [
        `0x${"01".repeat(48)}`,
        `0x${"02".repeat(48)}`,
        `0x${"03".repeat(48)}`,
      ];

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(0);
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0"),
      );

      // Add the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys);

      // Simulate accumulation of rewards for the two validators
      await updateBalance(this.stakingRewardsContract.target, 0.02);

      // Releasable fees amount to 10% of the staking rewards
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.002"));

      // Exit the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[0]);

      // Try to withdraw fees after exit but prior to validator sweep
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.be.revertedWithCustomError(
        this.stakingRewardsContract,
        "NoFundsToRelease",
      );
    });

    it("keeps track of validator exits to respect that fees do not apply to the submitted stake", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.customer.address, 1);

      const validatorPublicKeys = [
        `0x${"01".repeat(48)}`,
        `0x${"02".repeat(48)}`,
        `0x${"03".repeat(48)}`,
      ];

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(0);
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0"),
      );

      // Add the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(0, 1));

      // Simulate accumulation of rewards for the first validator
      await updateBalance(this.stakingRewardsContract.target, 0.01);

      // Add the validator 0x02^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(1, 2));

      // Simulate accumulation of rewards for the two validators
      await updateBalance(this.stakingRewardsContract.target, 0.02);

      // Exit the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[0]);

      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingRewardsContract.target, 32.02);

      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(32050000000000000000n);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 32 ETH initial stake)
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.005"));

      // Releasable rewards amount to 90% of the staking rewrads plus 32 ETH initial stake
      await expect(
        this.stakingRewardsContract.connect(this.customer).release(),
      ).to.changeEtherBalance(this.customer, ethers.parseEther("32.045"));
    });

    it("keeps track of subsequently released stakes", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.customer.address, 1);

      const validatorPublicKeys = [
        `0x${"01".repeat(48)}`,
        `0x${"02".repeat(48)}`,
        `0x${"03".repeat(48)}`,
      ];

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(0);
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0"),
      );

      // Add the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(0, 1));
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(1);

      // Simulate accumulation of rewards for the first validator
      await updateBalance(this.stakingRewardsContract.target, 0.01);

      // Add the validator 0x02^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(1, 2));
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(2);

      // Simulate accumulation of rewards for the two validators
      await updateBalance(this.stakingRewardsContract.target, 0.02);

      // Exit the validator 0x01^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[0]);
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(1);

      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingRewardsContract.target, 32.02);

      // Add the validator 0x03^48
      await this.stakingRewardsContract
        .connect(this.deployer)
        .activateValidators(validatorPublicKeys.slice(2, 3));
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(2);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 32 ETH initial stake)
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.005"));

      // Releasable rewards amount to 90% of the staking rewrads plus 32 ETH initial stake
      await expect(
        this.stakingRewardsContract.connect(this.customer).release(),
      ).to.changeEtherBalance(this.customer, ethers.parseEther("32.045"));

      // Exit the validator 0x02^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[1]);
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(1);
      // Exit the validator 0x03^48
      await this.stakingRewardsContract
        .connect(this.customer)
        .exitValidator(validatorPublicKeys[2]);
      expect(
        await this.stakingRewardsContract.numberOfActiveValidators(),
      ).to.equal(0);

      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingRewardsContract.target, 32.02);
      // Simulate validator sweep returning the initially staked 32 ETH plus residual rewards
      await updateBalance(this.stakingRewardsContract.target, 32.03);

      // Releasable fees amount to 10% of the staking rewards (which don't include the 64 ETH released stake)
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.005"));

      // Releasable rewards amount to 90% of the staking rewrads plus 32 ETH initial stake
      await expect(
        this.stakingRewardsContract.connect(this.customer).release(),
      ).to.changeEtherBalance(this.customer, ethers.parseEther("64.045"));
    });

    it("allows to withdraw accumulated fees and rewards", async function () {
      await setBalance(this.w3labs.address, 1);
      await setBalance(this.customer.address, 1);

      // The staking rewards contract is initially empty
      expect(
        await ethers.provider.getBalance(this.stakingRewardsContract.target),
      ).to.equal(0);
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0"),
      );

      // Staking rewards are accumulated in the contract
      await updateBalance(this.stakingRewardsContract.target, 0.01);

      // Releasable fees amount to 10% of the contract balance
      await expect(
        this.stakingRewardsContract.connect(this.w3labs).release(),
      ).to.changeEtherBalance(this.w3labs, ethers.parseEther("0.001"));

      // Expect to keep track of the amount released
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0.001"),
      );
      expect(
        await this.stakingRewardsContract.released(this.customer.address),
      ).to.equal(ethers.parseEther("0.0"));
      expect(
        await this.stakingRewardsContract.released(this.w3labs.address),
      ).to.equal(ethers.parseEther("0.001"));

      // Releasable rewards amount to 90% of the contract balance
      await expect(
        this.stakingRewardsContract.connect(this.customer).release(),
      ).to.changeEtherBalance(this.customer, ethers.parseEther("0.009"));

      // Expect to keep track of the amount released
      expect(await this.stakingRewardsContract.totalReleased()).to.equal(
        ethers.parseEther("0.01"),
      );
      expect(
        await this.stakingRewardsContract.released(this.customer.address),
      ).to.equal(ethers.parseEther("0.009"));
      expect(
        await this.stakingRewardsContract.released(this.w3labs.address),
      ).to.equal(ethers.parseEther("0.001"));
    });

    describe("deposit data registration", async () => {
      it("supports registration", async function () {
        const numberOfValidators = 1;
        const validatorDeposits = createValidatorDeposits(
          this.stakingRewardsContract.target,
          numberOfValidators,
        );

        console.log({
          validatorDeposits,
        });

        const res = this.stakingRewardsContract
          .connect(this.deployer)
          .registerDepositData(
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.pubkeys.map(() => 32000000000000000000n),
          );

        await expect(res).to.emit(
          this.stakingRewardsContract,
          "DepositDataRegistered",
        );

        const validation = await this.stakingRewardsContract
          .connect(this.deployer)
          .getDepositData(0);

        console.log({ validation });

        const verification = await this.stakingRewardsContract
          .connect(this.deployer)
          .verifyValidatorDepositData(
            validation[0],
            validation[2],
            validation[1],
            validation[3],
          );

        console.log({ verification });
      });
    });
  });
});
