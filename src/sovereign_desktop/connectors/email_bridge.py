"""Email bridge connector stub for Sovereign Desktop Ops HQ.

Real implementation reads local mail client settings or IMAP/SMTP creds
from environment/secrets and exposes read_inbox and send_message.
No credentials are stored in this repo.
"""
from .base import Connector

class EmailBridgeConnector(Connector):
    def status(self, running_patterns=None):
        return {
            "id": self.app_id,
            "display": "Email Bridge",
            "family": "email",
            "running": False,
            "detected": False,
            "launch_type": "none",
            "launch_value": "",
            "connection_methods": ["email"]
        }

    def launch(self, confirmed=False):
        return {"ok": False, "error": "Email bridge does not launch an app; configure IMAP/SMTP or local mail client."}
