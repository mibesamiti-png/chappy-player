"""Validate the handoff snapshot without requiring network, credentials, or Flutter."""
from __future__ import annotations

import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STATE = ROOT / "docs/project/STATE.json"
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
ALLOWED = {"todo", "in_progress", "done", "blocked"}


class HandoffContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.state = json.loads(STATE.read_text(encoding="utf-8"))

    def test_shape_and_cited_main_baseline(self):
        x = self.state
        self.assertEqual(x["schemaVersion"], 1)
        self.assertEqual(x["workingMode"], "single-chat-fast-v2")
        self.assertRegex(x["sourceMainAtCapture"], HEX40)
        self.assertRegex(x["lastCompletedBatch"]["mergedCommit"], HEX40)
        self.assertEqual(x["sourceMainAtCapture"], x["lastCompletedBatch"]["mergedCommit"])
        self.assertTrue(x["important"].startswith("This is a historical checkpoint"))
        self.assertEqual(x["policy"]["sourceOfTruth"].split(".")[0],
                         "GitHub main code + current PR/CI + this snapshot")

    def test_next_batch_identifiers_are_unique_and_planned(self):
        batch = self.state["nextBatch"]
        self.assertEqual(self.state["focus"]["id"], batch["id"])
        self.assertEqual(len(batch["tasks"]), batch["targetTasks"])
        self.assertTrue(5 <= len(batch["tasks"]) <= 10)
        ids = [task["id"] for task in batch["tasks"]]
        self.assertEqual(len(ids), len(set(ids)))
        for task in batch["tasks"]:
            self.assertIn(task["status"], ALLOWED)
            self.assertTrue(task["name"])
        self.assertIn("PCコマンド実行", batch["stopBefore"])

    def test_source_qa_and_release_are_separated(self):
        state = self.state
        qa = state["observations"]["pcLinkTwoDevice"]
        self.assertIn(qa["status"], ("not_run", "in_progress", "passed", "failed"))
        self.assertTrue(0 <= qa["casesPassed"] <= qa["casesTotal"])
        if qa["status"] == "not_run":
            self.assertEqual(qa["casesPassed"], 0)
        self.assertTrue((ROOT / qa["source"]).is_file())
        self.assertIn(state["observations"]["debugAndroidColdLaunch"]["status"],
                      ("user_reported_pass", "not_run", "failed"))
        self.assertEqual(state["observations"]["publicMiniappCatalog"]["debug"], 8)
        self.assertEqual(state["observations"]["publicMiniappCatalog"]["stable"], 2)
        self.assertEqual(state["policy"]["stableRelease"],
                         "manual, separately approved; no automatic release")

    def test_linked_handoff_files_exist_and_have_safe_guidance(self):
        paths = ("docs/project/HANDOFF.md",
                 "docs/project/ROADMAP.md",
                 "docs/project/SINGLE_CHAT_DEVELOPMENT.md")
        content = "\n".join((ROOT / path).read_text(encoding="utf-8")
                            for path in paths)
        for required in ("R4B", "Quick CI", "実機", "Notion", "main"):
            self.assertIn(required, content)
        for bad in ("CHAPPY_STORE_PASSWORD=", "CHAPPY_KEY_PASSWORD=",
                    "CHAPPY_PUBLISH_TOKEN="):
            self.assertNotIn(bad, content)


if __name__ == "__main__":
    unittest.main()
