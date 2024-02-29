import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x87411145423fDf9123040799F9Ff894153339a75"; // To be updated.
  const vaultImplAddress = "0xae77949C4dBE890363E7A12b968E976E634242E9"; // to be updated.
  const token0 = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  const token1 = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";
  const name = "Test Token"; // To be updated.
  const symbol = "TT"; // To be updated.

  let factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    rangeProtocolFactoryAddress
  );
  const data = getInitializeData({
    managerAddress,
    name,
    symbol,
  });

  const tx = await factory.createVault(token0, token1, vaultImplAddress, data);
  const txReceipt = await tx.wait();
  const [
    {
      args: { vault },
    },
  ] = txReceipt.events.filter(
    (event: { event: any }) => event.event === "VaultCreated"
  );
  console.log("Vault: ", vault);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
