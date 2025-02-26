import {Octokit} from "octokit";
import {deleteBranch, githubToken, REPO_NAME, REPO_OWNER} from "./utils.js";

const octokit = new Octokit({
  auth: githubToken,
  userAgent: "AMLLTTMLDBBranchCleaner",
});

async function main() {
  const openingPulls = await octokit.rest.pulls.list({
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "closed",
  });

  const reg = /[0-9]+$/
  for (const pull of openingPulls.data) {
    try {
      if (reg.test(pull.head.ref)) {
        console.log(pull.head.ref);
        try {
          await deleteBranch(pull.head.ref);
        } catch { }
      }
    } catch {}
  }
}

main().catch(console.error);
