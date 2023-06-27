const { ether, ethers } = require("hardhat");
const { expect } = require("chai");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("SplitRewards", async function () {
  describe("contract deployment", async function () {
    it("rejects an empty set of payees", async () => {
      await expect(
        ethers.deployContract("SplitRewards", [[], []], {
          value: 0,
        })
      ).to.be.revertedWith("SplitRewards: no payees");
    });

    it("rejects more payees than shares", async () => {
      const [_owner, payee1, payee2, payee3, _nonpayee1, _payer1] =
        await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "SplitRewards",
          [
            [payee1, payee2, payee3],
            [20, 30],
          ],
          { value: 0 }
        )
      ).to.be.revertedWith("SplitRewards: payees and shares length mismatch");
    });

    it("rejects more shares than payees", async () => {
      const [_owner, payee1, payee2] = await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "SplitRewards",
          [
            [payee1, payee2],
            [20, 30, 40],
          ],
          { value: 0 }
        )
      ).to.be.revertedWith("SplitRewards: payees and shares length mismatch");
    });

    it("rejects null payees", async () => {
      const [_owner, payee1] = await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "SplitRewards",
          [
            [payee1, ZERO_ADDRESS],
            [20, 30],
          ],
          { value: 0 }
        )
      ).to.be.revertedWith("SplitRewards: account is the zero address");
    });

    it("rejects zero-valued shares", async () => {
      const [_owner, payee1, payee2] = await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "SplitRewards",
          [
            [payee1, payee2],
            [20, 0],
          ],
          { value: 0 }
        )
      ).to.be.revertedWith("SplitRewards: shares are 0");
    });

    it("rejects repeated payees", async () => {
      const [_owner, payee1] = await ethers.getSigners();

      await expect(
        ethers.deployContract(
          "SplitRewards",
          [
            [payee1, payee1],
            [20, 30],
          ],
          { value: 0 }
        )
      ).to.be.revertedWith("SplitRewards: account already has shares");
    });
  });

  describe("after deployment", async function () {
    beforeEach(async function () {
      const [owner, payee1, payee2, payee3] = await ethers.getSigners();

      this.payees = [payee1, payee2, payee3];
      this.shares = [20, 10, 70];

      this.contract = await ethers.deployContract(
        "SplitRewards",
        [this.payees, this.shares],
        { value: 0 }
      );

      this.token = await ethers.deployContract("JustfarmingCoin", [], {
        value: 0,
      });

      await this.contract.waitForDeployment();
      await this.token.waitForDeployment();

      await this.token.mint(owner, ethers.parseEther("1000"));
    });

    it("has total shares", async function () {
      // await this.contract.wait(1);
      expect(await this.contract.totalShares()).to.equal("100");
    });
  });
});
