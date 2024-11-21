# Espresso Migration

This document contains details surrounding the test migrating an exsisting Arbitrum Orbit chain to use the nitro-espresso-integration, and be compatible with the Espresso network.

## Running the test

Run the test by navigating to nitro-testnode/espresso-tests and run ./migration-test.bash


## Steps related to upgrade in production

Many of the steps in the test are nearly identical to the steps needed to upgrade an orbit network to be compatible with the espresso network.

Any commands in the migration-test.bash file that have comments above them prefixed with the string `** Essential migration step **` are core parts of the migration.

E.g.
```
# ** Essential migration step ** Forge script to deploy new OSP entry. We do this to later point the rollups challenge manager to the espresso integrated OSP.
forge script --chain $PARENT_CHAIN_CHAIN_ID contracts/parent-chain/contract-upgrades/DeployEspressoOsp.s.sol:DeployEspressoOsp --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv
```

 Other steps, such as noting contract addresses, are technically part of these essential core steps. However, these steps are not marked with " ** Essential migration step ** ". In a real migration, these steps will likely not occur in a single bash script, or necessarily have the same process.
 
These steps can be done manually while preparing the `** Essential migration step **` steps in whichever manner makes sense to the operators of the network doing their migration. Therefore they are marked with `* Essential migration sub step * `, and specific context is given as to how these steps may be different for operators.

## Non upgrade related steps

Steps that are not directly related to a real world example of this upgrade will be unmarked. That is comments about these steps will contain neither `** Essential migration step **` or `* Essential migration sub step *`