import subprocess
import threading
import time

import decky

BOOTSTRAP = "/var/local/lib/lg2-fix/lg2-fix-bootstrap.sh"
INTERVAL_S = 300


class Plugin:
    async def _main(self):
        def loop():
            while True:
                try:
                    subprocess.run(
                        [BOOTSTRAP],
                        timeout=60,
                        capture_output=True,
                        stdin=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception as e:  # noqa: BLE001
                    decky.logger.error(f"lg2-fix bootstrap failed: {e}")
                time.sleep(INTERVAL_S)

        threading.Thread(target=loop, daemon=True).start()
        decky.logger.info("lg2-fix re-seed loop started")
