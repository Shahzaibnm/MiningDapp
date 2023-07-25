const { deployProxy } = require("@openzeppelin/truffle-upgrades");
const miningDapp = artifacts.require("miningDapp");

module.exports = async function (deployer) {
  const instance = await deployProxy(
    miningDapp,
    [
     ],
    { deployer }
  );
  console.log("Deployed", instance.address);
};