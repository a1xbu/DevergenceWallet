from base_contract import BaseContract


class Faucet(BaseContract):

    def setUserCode(self, code):
        return self.call_function("setUserCode", {"code": code})

    def ClaimSuccess(self, pubkey, claim_id, op_hash, surf_address, faucet_balance):
        return self.call_function("ClaimSuccess", {
            "user_pubkey": hex(pubkey),
            "claim_id": hex(claim_id),
            "op_hash": op_hash,
            "surf_address": surf_address,
            "faucet_balance": hex(faucet_balance)
        }, async_call=True)

    def claim(self, deploy, surf_address):
        return self.call_function("claim", {
            "deploy": deploy,
            "surf_address": surf_address
        }, async_call=False)

    def query_queue(self):
        return self.run_function("query_queue", {})
