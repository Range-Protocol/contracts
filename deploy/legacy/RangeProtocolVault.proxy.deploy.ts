import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x3e51dE80257D152356AD4250dEfFf974fCf24537"; // To be updated.
  const vaultImplAddress = "0x295C49c85C3A28f69C1D13e69304241ca1ABB9EA"; // to be updated.
  const token0 = "0x2170ed0880ac9a755fd29b2688956bd959f933f8";
  const token1 = "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d";
  const fee = 500; // To be updated.
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

  const tx = await factory.createVault(token0, token1, fee, vaultImplAddress, data);
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
