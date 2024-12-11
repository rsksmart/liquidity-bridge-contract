module.exports = async function (callback) {
  console.log("===Getting transaction data===");

  const hash =
    "0x1eec81525f3052027b4265ab7d65bb71ce59e6d91cf7777533af02ad50cae781";

  try {
    console.log("Getting transaction info====");
    const tx = await web3.eth.getTransaction(hash);

    console.log(tx);

    console.log("Getting receipt====")

    const txReceipt = await web3.eth.getTransactionReceipt(hash);

    console.log(txReceipt);
  } catch (error) {
    console.log("Error: ", error);
  }

  console.log("===Finished===");
  callback();
};
