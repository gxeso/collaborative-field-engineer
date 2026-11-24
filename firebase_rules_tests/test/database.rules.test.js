import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, ref, set } from 'firebase/database';
import { readFile } from 'node:fs/promises';
import {
  after,
  before,
  beforeEach,
  describe,
  it,
} from 'mocha';

const projectId = 'cfe-sync-ghassan-2026';
const workspaceId = 'juma-field-engineering';

const viewerUid = 'viewer-user';
const editorUid = 'editor-user';
const adminUid = 'admin-user';
const nonMemberUid = 'non-member-user';

let testEnvironment;

function workspacePath(relativePath = '') {
  const root = `workspaces/${workspaceId}`;
  return relativePath.length === 0 ? root : `${root}/${relativePath}`;
}

function validSite(siteId) {
  return {
    id: siteId,
    name: 'Emulator Security Test Site',
    latitude: 25.2048,
    longitude: 55.2708,
    lastOperationId: `operation-${siteId}`,
    remoteUpdatedAt: '2026-10-06T06:30:00.000Z',
  };
}

describe('Realtime Database workspace security rules', () => {
  before(async () => {
    const rules = await readFile(
      '../database.rules.json',
      'utf8',
    );

    testEnvironment = await initializeTestEnvironment({
      projectId,
      database: {
        host: '127.0.0.1',
        port: 9000,
        rules,
      },
    });
  });

  beforeEach(async () => {
    await testEnvironment.clearDatabase();

    await testEnvironment.withSecurityRulesDisabled(
      async (context) => {
        const database = context.database();

        await set(
          ref(database, `workspaceMembers/${workspaceId}`),
          {
            [viewerUid]: {
              role: 'viewer',
            },
            [editorUid]: {
              role: 'editor',
            },
            [adminUid]: {
              role: 'admin',
            },
          },
        );

        await set(
          ref(database, workspacePath()),
          {
            processedOperations: {
              seedOperation: {
                operationId: 'seedOperation',
                entityType: 'site',
                entityId: 'seed-site',
                operationType: 'create',
                processedAt: '2026-10-06T06:00:00.000Z',
              },
            },
            surveySites: {
              'seed-site': {
                id: 'seed-site',
                name: 'Seed Site',
                lastOperationId: 'seedOperation',
                remoteUpdatedAt: '2026-10-06T06:00:00.000Z',
              },
            },
          },
        );
      },
    );
  });

  after(async () => {
    await testEnvironment.cleanup();
  });

  it('denies unauthenticated workspace reads', async () => {
    const database = testEnvironment
      .unauthenticatedContext()
      .database();

    await assertFails(
      get(ref(database, workspacePath())),
    );
  });

  it('denies workspace reads by authenticated non-members', async () => {
    const database = testEnvironment
      .authenticatedContext(nonMemberUid)
      .database();

    await assertFails(
      get(ref(database, workspacePath())),
    );
  });

  it('allows viewers to read workspace data', async () => {
    const database = testEnvironment
      .authenticatedContext(viewerUid)
      .database();

    await assertSucceeds(
      get(ref(database, workspacePath('surveySites'))),
    );
  });

  it('denies viewers from writing workspace data', async () => {
    const database = testEnvironment
      .authenticatedContext(viewerUid)
      .database();

    await assertFails(
      set(
        ref(database, workspacePath('surveySites/viewer-site')),
        validSite('viewer-site'),
      ),
    );
  });

  it('denies editors from writing under the admin-only policy', async () => {
    const database = testEnvironment
      .authenticatedContext(editorUid)
      .database();

    await assertFails(
      set(
        ref(database, workspacePath('surveySites/editor-site')),
        validSite('editor-site'),
      ),
    );
  });

  it('allows admins to write valid survey sites', async () => {
    const database = testEnvironment
      .authenticatedContext(adminUid)
      .database();

    await assertSucceeds(
      set(
        ref(database, workspacePath('surveySites/admin-site')),
        validSite('admin-site'),
      ),
    );
  });

  it('rejects malformed survey sites from admins', async () => {
    const database = testEnvironment
      .authenticatedContext(adminUid)
      .database();

    await assertFails(
      set(
        ref(database, workspacePath('surveySites/malformed-site')),
        {
          id: 'wrong-id',
          name: 'Malformed Site',
        },
      ),
    );
  });

  it('denies client-side membership changes, including admins', async () => {
    const database = testEnvironment
      .authenticatedContext(adminUid)
      .database();

    await assertFails(
      set(
        ref(
          database,
          `workspaceMembers/${workspaceId}/new-user/role`,
        ),
        'admin',
      ),
    );
  });

  it('rejects unknown workspace collections', async () => {
    const database = testEnvironment
      .authenticatedContext(adminUid)
      .database();

    await assertFails(
      set(
        ref(database, workspacePath('privateSecrets/test')),
        {
          value: 'must-not-be-created',
        },
      ),
    );
  });
});