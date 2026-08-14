interface DeploymentTaskIdentity {
  id: string
  releaseId: string
  action: "deploy" | "rollback"
}

// A lost HTTP response does not mean the Server rejected the command. Match a
// newly persisted task before offering a retry, which could dispatch twice.
export function findReconciledDeploymentTask<T extends DeploymentTaskIdentity>(
  tasks: T[],
  knownTaskIds: ReadonlySet<string>,
  releaseId: string,
  action: "deploy" | "rollback",
): T | undefined {
  return tasks.find((task) =>
    !knownTaskIds.has(task.id) && task.releaseId === releaseId && task.action === action
  )
}
