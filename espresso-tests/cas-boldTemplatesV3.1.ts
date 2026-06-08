import { JsonRpcProvider } from '@ethersproject/providers'

export type CreatorTemplates = {
  eth: {
    bridge: string
    sequencerInbox: string
    delayBufferableSequencerInbox: string
    inbox: string
    rollupEventInbox: string
    outbox: string
  }
  erc20: {
    bridge: string
    sequencerInbox: string
    delayBufferableSequencerInbox: string
    inbox: string
    rollupEventInbox: string
    outbox: string
  }
  rollupUserLogic: string
  rollupAdminLogic: string
  challengeManagerTemplate: string
  osp: string
  rollupCreator: string
}

export const templates: {
  [key: number]: CreatorTemplates
} = {
  1337: {
    eth: {
      bridge: '0xC678f7B95A7D1F77c6024c0086301D21402854b1',
      sequencerInbox: '0xda51f4f63B6c1541D049A0F3d641493463559A92',
      delayBufferableSequencerInbox:
        '0x595841B05587dc6EFB52da4ce6A04B5DfFdB82C5',
      inbox: '0x8D3b93dfFFf4842E7B61FB553b383db2C6BC91c6',
      rollupEventInbox: '0x796FeE4adceD1cb47a3e3d1B6925472F8fC8f1f9',
      outbox: '0x396765AEbE540575ef927F769b0d7b89594f931c',
    },
    erc20: {
      bridge: '0x0124687D1F2869b0C2335B98ddc7FCf59DA2CEa1',
      sequencerInbox: '0x1E664bf1d6E5b5943a03827ed553D2A71f4bF3D0',
      delayBufferableSequencerInbox:
        '0x0aa9AA5Ebd323c1e37Ba081B512Ae1e2fA8Cf783',
      inbox: '0xBfd8916b9DCB60B3b437D2B3a6FF56F78DcD9Ff2',
      rollupEventInbox: '0x2706682dD3bD709b055E0266D98BA380FE22B807',
      outbox: '0x5128805C5331A3D445B72545d2461B2C3B05218c',
    },
    rollupUserLogic: '0xedC23dFC7D1e57EC07eA5ff7419634DbAe08Ed2C',
    rollupAdminLogic: '0xAb7A44CE7e66963d2116dCe74AB63eeF88266C82',
    challengeManagerTemplate: '0xCAaa9332F940362aEAAADD1B0A59c229C4fD8f79',
    osp: '0x5087a6fD526eFD5c6770d94D0c325de0e2A2c44D',
    rollupCreator: '0x611b4875141798A61d56Ae19Af8A9531aD237D88',
  },
}

export async function verifyCreatorTemplates(
  l1Rpc: JsonRpcProvider,
  templates: CreatorTemplates
) {
  const checkAddress = async (name: string, address: string) => {
    if ((await l1Rpc.getCode(address)).length <= 2) {
      throw new Error(`No code found for template ${name} at ${address}`)
    }
  }

  for (const [key, value] of Object.entries(templates)) {
    if (typeof value === 'string') {
      await checkAddress(key, value)
    } else {
      for (const [subkey, subvalue] of Object.entries(value)) {
        await checkAddress(`${key}.${subkey}`, subvalue)
      }
    }
  }
}
