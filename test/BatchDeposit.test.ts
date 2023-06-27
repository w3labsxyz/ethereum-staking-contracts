const { ethers } = require("hardhat");
const { expect } = require("chai");

// Fake deposits
const fakeData = {
  pubkeys: [
    "0xb397443cf61fbb6286550d9ef9b58a033deeb0378fe504ec09978d94eb87aedea244892853b994e27d6f77133fce723e",
    "0xa50e1dfc528fe61d7c0b3bc118f94e7090e1b0b80328a8ec66783cecd74d3fc51459c76f2940dc905b9a32b34220945b",
    "0x881e7056817dce7ac795b592f309c7b681ea7e5eadc5cfd39871112b69103e396ce91d0a3a9a333cb4f213ed43add094",
  ],
  creds: [
    "0x00e53ca56e7f6412ca6024989d8a37cb0520d70d7e3472bf08fc629816603b5c",
    "0x00e53ca56e7f6412ca6024989d8a37cb0520d70d7e3472bf08fc629816603b5c",
    "0x00e53ca56e7f6412ca6024989d8a37cb0520d70d7e3472bf08fc629816603b5c",
  ],
  signatures: [
    "0xa45d0dd7c44a73209d2377fbc3ded47e5af5ee38ade2e08c53551dd34b98248b8a1e1feb1912fb024033435927d47ad70adf10b1ee4a65bfc8ae1501962dee655bfeb5cefdff3389c2d9eadcc6fdc4e8ed340f0414b684168146c15aa4edbfed",
    "0xa84fdfaceb817187a4436a8deafa6071bb32ae2510224d2423298de9e15a61dcdbbed42b1afded00c8ce5e8c02a8ba7b01b31a9a19e2fdb8b5c57859a481ffdd946271ca019b76b47cead66b05b8fd3422bbbeaf719da75f3d2e67bd215ae954",
    "0x829b742e94203e5df52403bbd07a119abc67fa0b14326de99997f4619d3d62fbf122027a71fc6bae13f402380658fa32008d5c43b121a46d8417e99556f95c129da2763ab44ad4d9c657c8a59d1fe1783d732b2a28d77efc42bc648cf8cf21c1",
  ],
  dataRoots: [
    "0x2c16c5739ec31a951e5551e828ef57ee2d6944b36cf674db9f884173289c7946",
    "0xae358f6ef71c4eaa96cbb68b6e8e304c2348cce8f53424409a5bd76f29d357f3",
    "0xb2bd009079582e1f6992c04773c867bf39ce1cfb9edd56ca22d7889f2eba508b",
  ],
};

describe("BatchDeposit", async function () {
  beforeEach(async function () {
    this.deposit_contract = await ethers.deployContract("DepositContract", [], {
      value: 0,
    });

    await this.deposit_contract.waitForDeployment();

    this.contract = await ethers.deployContract(
      "BatchDeposit",
      [this.deposit_contract.target],
      { value: 0 }
    );

    await this.contract.waitForDeployment();
  });

  it("can perform multiple deposits in one tx", async function () {
    const [_owner, payee1] = await ethers.getSigners();
    const numberOfNodes = 3;
    const amountWei = ethers.parseEther((32 * numberOfNodes).toString(), "wei");

    const res = await this.contract
      .connect(payee1)
      .batchDeposit(
        fakeData.pubkeys,
        fakeData.creds,
        fakeData.signatures,
        fakeData.dataRoots,
        {
          value: amountWei,
        }
      );

    await expect(res).to.changeEtherBalance(payee1, -amountWei);
    await expect(res).to.changeEtherBalance(this.contract.target, 0);
    await expect(res).to.changeEtherBalance(
      this.deposit_contract.target,
      amountWei
    );
    await expect(res)
      .to.emit(this.contract, "DepositEvent")
      .withArgs(payee1.address, numberOfNodes);
  });

  it("reverts if transaction value is too low", async function () {
    const [_owner, payee1] = await ethers.getSigners();
    const amountWei = ethers.parseEther("1", "wei");

    await expect(
      this.contract
        .connect(payee1)
        .batchDeposit(
          fakeData.pubkeys,
          fakeData.creds,
          fakeData.signatures,
          fakeData.dataRoots,
          {
            value: amountWei,
          }
        )
    ).to.be.revertedWith(
      "BatchDeposit: The amount of ETH does not match the amount of nodes"
    );
  });

  it("reverts if transaction value is too high", async function () {
    const [_owner, payee1] = await ethers.getSigners();
    const amountWei = ethers.parseEther("100", "wei");

    await expect(
      this.contract
        .connect(payee1)
        .batchDeposit(
          fakeData.pubkeys,
          fakeData.creds,
          fakeData.signatures,
          fakeData.dataRoots,
          {
            value: amountWei,
          }
        )
    ).to.be.revertedWith(
      "BatchDeposit: The amount of ETH does not match the amount of nodes"
    );
  });

  it("can transfer ownership", async function () {
    const [owner, owner2] = await ethers.getSigners();

    expect(await this.contract.owner()).to.equal(owner.address);

    await this.contract.transferOwnership(owner2.address);

    expect(await this.contract.owner()).to.equal(owner2.address);
  });
});
