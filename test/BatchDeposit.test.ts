import { ethers } from "hardhat";
import { expect } from "chai";
import utils from "./utils";

const { createValidatorDeposits } = utils;

describe("BatchDeposit", async () => {
  beforeEach(async function () {
    const [_deployer, w3labsFeeWallet, customer] = await ethers.getSigners();

    this.ethereumStakingDepositContract = await ethers.deployContract(
      "DepositContract",
      [],
      {
        value: 0,
      },
    );

    await this.ethereumStakingDepositContract.waitForDeployment();

    this.batchDepositContract = await ethers.deployContract(
      "BatchDeposit",
      [this.ethereumStakingDepositContract.target],
      { value: 0 },
    );

    await this.batchDepositContract.waitForDeployment();

    this.stakingRewardsContract = await ethers.deployContract(
      "StakingRewards",
      [
        this.batchDepositContract.target,
        w3labsFeeWallet.address,
        customer.address,
        1000,
      ],
    );
  });

  describe("not payable", async () => {
    it("throws a custom error `NotPayable` when trying to send ETH", async function () {
      const [_deployer, _w3labsFeeWallet, _customer, randomUser] =
        await ethers.getSigners();

      await expect(
        randomUser.sendTransaction({
          to: this.batchDepositContract.target,
          value: ethers.parseEther("1.0"),
        }),
      ).to.be.revertedWithCustomError(this.batchDepositContract, "NotPayable");
    });
  });

  describe("validator registration", async () => {
    it("is allowed with valid validator public keys", async function () {
      const [owner, nobody] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(48)}`;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators([validator1Pubkey]);

      expect(
        await this.batchDepositContract
          .connect(nobody)
          .isValidatorAvailable(validator1Pubkey),
      ).to.be.true;
    });

    it("reverts if a validator is already registered", async function () {
      const [owner] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(48)}`;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators([validator1Pubkey]);

      await expect(
        this.batchDepositContract
          .connect(owner)
          .registerValidators([validator1Pubkey]),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "ValidatorAlreadyRegistered",
      );
    });

    it("reverts if a validator has already been registered *and* activated", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 1;

      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          {
            value: validatorDeposits.amount,
          },
        );

      await expect(
        this.batchDepositContract
          .connect(owner)
          .registerValidators(validatorDeposits.pubkeys),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "ValidatorIsOrWasActive",
      );
    });

    it("reverts if a validator public key is invalid", async function () {
      const [owner] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(47)}`;

      await expect(
        this.batchDepositContract
          .connect(owner)
          .registerValidators([validator1Pubkey]),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "PublicKeyLengthMismatch",
      );
    });
  });

  describe("batch deposits", async () => {
    it("can perform multiple deposits in one tx", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      const res = await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          {
            value: validatorDeposits.amount,
          },
        );

      const expectedPaymentAmount = ethers.parseEther(
        (32 * numberOfNodes).toString(),
      );
      await expect(res).to.changeEtherBalance(payee1, -expectedPaymentAmount);
      await expect(res).to.changeEtherBalance(
        this.batchDepositContract.target,
        0,
      );
      await expect(res).to.changeEtherBalance(
        this.ethereumStakingDepositContract.target,
        expectedPaymentAmount,
      );
      await expect(res)
        .to.emit(this.batchDepositContract, "Deposited")
        .withArgs(payee1.address, numberOfNodes);
    });

    it("reverts if transaction value is too low", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const amountWei = ethers.parseEther("1");
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        1,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: amountWei,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "InvalidTransactionAmount",
      );
    });

    it("reverts if transaction value is too high", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const amountWei = ethers.parseEther("100");
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        1,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: amountWei,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "InvalidTransactionAmount",
      );
    });

    it("reverts if the number of pubkeys does not match the number of signatures", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures.slice(0, 1),
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "SignaturesLengthMismatch",
      );
    });

    it("reverts if the number of pubkeys does not match the number of deposit data roots", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots.slice(0, 1),
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "DepositDataRootsLengthMismatch",
      );
    });

    it("reverts if a public key is invalid", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 2;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            [validatorDeposits.pubkeys[0], "0x0000"],
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "PublicKeyLengthMismatch",
      );
    });

    it("reverts if a signature is invalid", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 2;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            [validatorDeposits.signatures[0], "0x0000"],
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "SignatureLengthMismatch",
      );
    });

    it("reverts if a validator is not available", async function () {
      const [_owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 1;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWithCustomError(
        this.batchDepositContract,
        "ValidatorNotAvailable",
      );
    });

    it("updates the available validators after a successful deposit", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys.slice(0, 1));

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.false;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys.slice(1, 3));

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.true;

      await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys.slice(0, 1),
          validatorDeposits.signatures.slice(0, 1),
          validatorDeposits.depositDataRoots.slice(0, 1),
          {
            value: ethers.parseEther((32 * 1).toString()),
          },
        );

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.true;

      await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys.slice(1, 3),
          validatorDeposits.signatures.slice(1, 3),
          validatorDeposits.depositDataRoots.slice(1, 3),
          {
            value: ethers.parseEther((32 * 2).toString()),
          },
        );

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.false;
    });
  });

  it("can transfer ownership", async function () {
    const [owner, owner2] = await ethers.getSigners();
    expect(await this.batchDepositContract.owner()).to.equal(owner.address);
    await this.batchDepositContract.transferOwnership(owner2.address);
    expect(await this.batchDepositContract.owner()).to.equal(owner2.address);
  });
});
