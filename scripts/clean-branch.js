import {Octokit} from "octokit";
import {githubToken, REPO_NAME, REPO_OWNER} from "./utils.js";

const octokit = new Octokit({
  auth: githubToken,
  userAgent: "AMLLTTMLDBBranchCleaner",
});

async function main() {
  console.log("???")
  const openingPulls = await octokit.rest.pulls.list({
    state: "closed",
  });

  const reg = /[0-9]+$/
  for (const pull of openingPulls.data) {
    try {
      console.log(pull.head.ref);
    } catch (e) {}
  }
}

main().catch(console.error);
