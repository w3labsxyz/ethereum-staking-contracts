const BatchDeposit = artifacts.require("BatchDeposit");
const SplitRewards = artifacts.require("SplitRewards");

module.exports = async function migrate(deployer, network, accounts) {
  if (network === "test") {
    const initialFee = 1000000000;

    const [_owner, justfarmingFeeWallet, customer1, _customer2] = accounts;

    await deployer.deploy(
      SplitRewards,
      [justfarmingFeeWallet, customer1],
      [10, 90]
    );
    const _splitRewards = await SplitRewards.deployed();

    const DepositContract = artifacts.require("DepositContract");
    // migration specific to development and testing

    await deployer.deploy(DepositContract);
    const depositContract = await DepositContract.deployed();

    await deployer.deploy(BatchDeposit, depositContract.address, initialFee);
    const _batchDeposit = await BatchDeposit.deployed();
  } else {
    // migration for live network
  }
};
