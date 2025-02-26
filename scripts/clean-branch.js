import {Octokit} from "octokit";
import {githubToken, REPO_NAME, REPO_OWNER} from "./utils.js";

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
      if (reg.test(pull.title)) {
        console.log(pull.head.ref);
      }
    } catch (e) {}
  }
}
