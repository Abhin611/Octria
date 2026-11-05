// Checks firestore.rules against the local emulator: npm test, in this folder.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const CODE = 'ABC234';
let env;

const db = (uid) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
const room = (uid, cid = 'r1') => doc(db(uid), 'classrooms', cid);

const step = (owner, extra = {}) => ({
  phaseId: 'p1',
  ownerUid: owner,
  title: 'A step',
  status: 'todo',
  dependsOn: [],
  order: 1,
  ...extra,
});

async function seed({ approval = false, mode = 'group', members = ['master', 'co', 'amy', 'ben'] } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'classrooms/r1'), {
      title: 'Room',
      mode,
      masterUid: 'master',
      coMasterUids: ['co'],
      memberUids: members,
      inviteCode: CODE,
      approvalRequired: approval,
    });
    await setDoc(doc(d, 'inviteCodes', CODE), { classroomId: 'r1' });
    for (const m of members) {
      await setDoc(doc(d, 'classrooms/r1/members', m), { name: m });
    }
    await setDoc(doc(d, 'classrooms/r1/phases/p1'), { title: 'Phase', order: 1 });
    await setDoc(doc(d, 'classrooms/r1/steps/amys'), step('amy'));
    await setDoc(doc(d, 'classrooms/r1/steps/bens'), step('ben', { dependsOn: ['amys'] }));
  });
}

async function join(uid, code = CODE) {
  const d = db(uid);
  const r = doc(d, 'classrooms/r1');
  const b = writeBatch(d);
  b.set(doc(d, 'classrooms/r1/members', uid), { name: uid, inviteCode: code });
  b.update(r, { memberUids: arrayUnion(uid) });
  return b.commit();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-octria',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

describe('reading', () => {
  it('members can read a classroom and its plan', async () => {
    await seed();
    await assertSucceeds(getDoc(room('amy')));
    await assertSucceeds(getDocs(collection(db('amy'), 'classrooms/r1/steps')));
    await assertSucceeds(
      getDocs(query(collection(db('amy'), 'classrooms'), where('memberUids', 'array-contains', 'amy'))),
    );
  });
  it('outsiders and signed-out people cannot', async () => {
    await seed();
    await assertFails(getDoc(room('eve')));
    await assertFails(getDoc(room(null)));
    await assertFails(getDocs(collection(db('eve'), 'classrooms/r1/steps')));
    await assertFails(getDocs(collection(db('eve'), 'classrooms')));
  });
  it('one invite code can be looked up, but not the list', async () => {
    await seed();
    await assertSucceeds(getDoc(doc(db('eve'), 'inviteCodes', CODE)));
    await assertFails(getDocs(collection(db('eve'), 'inviteCodes')));
    await assertFails(getDoc(doc(db(null), 'inviteCodes', CODE)));
  });
});

describe('creating a classroom', () => {
  const made = (uid, extra = {}) => ({
    title: 'New',
    mode: 'group',
    masterUid: uid,
    coMasterUids: [],
    memberUids: [uid],
    inviteCode: 'NEW234',
    approvalRequired: false,
    ...extra,
  });
  it('the creator becomes master, with a code', async () => {
    const d = db('amy');
    const b = writeBatch(d);
    b.set(doc(d, 'classrooms/new'), made('amy'));
    b.set(doc(d, 'classrooms/new/members/amy'), { name: 'amy' });
    b.set(doc(d, 'inviteCodes/NEW234'), { classroomId: 'new' });
    await assertSucceeds(b.commit());
  });
  it('nobody can create one in someone else’s name', async () => {
    await assertFails(setDoc(doc(db('amy'), 'classrooms/new'), made('ben')));
    await assertFails(setDoc(doc(db('amy'), 'classrooms/new'), made('amy', { memberUids: ['amy', 'ben'] })));
  });
  it('nobody can claim another classroom’s code', async () => {
    await seed();
    await assertFails(setDoc(doc(db('eve'), 'inviteCodes/NEW234'), { classroomId: 'r1' }));
  });
});

describe('joining', () => {
  it('the right code lets you in', async () => {
    await seed();
    await assertSucceeds(join('eve'));
    await assertSucceeds(getDoc(room('eve')));
  });
  it('the wrong code does not', async () => {
    await seed();
    await assertFails(join('eve', 'WRONG2'));
  });
  it('a full classroom of 10 refuses', async () => {
    await seed({ members: ['master', 'co', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] });
    await assertFails(join('eve'));
  });
  it('an individual classroom refuses', async () => {
    await seed({ mode: 'individual', members: ['master'] });
    await assertFails(join('eve'));
  });
  it('you cannot add anyone else, or remove anyone', async () => {
    await seed();
    await assertFails(updateDoc(room('eve'), { memberUids: ['master', 'co', 'amy', 'ben', 'mal'] }));
    const d = db('eve');
    const b = writeBatch(d);
    b.set(doc(d, 'classrooms/r1/members/eve'), { name: 'eve', inviteCode: CODE });
    b.update(doc(d, 'classrooms/r1'), { memberUids: ['master', 'eve'] });
    await assertFails(b.commit());
  });
  it('joining changes nothing else about the classroom', async () => {
    await seed();
    const d = db('eve');
    const b = writeBatch(d);
    b.set(doc(d, 'classrooms/r1/members/eve'), { name: 'eve', inviteCode: CODE });
    b.update(doc(d, 'classrooms/r1'), { memberUids: arrayUnion('eve'), masterUid: 'eve' });
    await assertFails(b.commit());
  });
});

describe('joining with approval on', () => {
  const request = (uid, code = CODE) =>
    setDoc(doc(db(uid), 'classrooms/r1/joinRequests', uid), { name: uid, inviteCode: code });
  beforeEach(() => seed({ approval: false }));
  const needApproval = () =>
    env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'classrooms/r1'), { joinApprovalRequired: true }),
    );
  it('the code alone no longer lets you in', async () => {
    await needApproval();
    await assertFails(join('eve'));
  });
  it('you can ask with the right code, but not the wrong one', async () => {
    await needApproval();
    await assertFails(request('eve', 'WRONG2'));
    await assertSucceeds(request('eve'));
    await assertFails(getDoc(room('eve')));
  });
  it('you cannot ask when approval is off', async () => {
    await assertFails(request('eve'));
  });
  it('only you can ask for yourself', async () => {
    await needApproval();
    await assertFails(setDoc(doc(db('eve'), 'classrooms/r1/joinRequests/mal'), { inviteCode: CODE }));
  });
  async function approve(uid, by) {
    const d = db(by);
    const b = writeBatch(d);
    b.set(doc(d, 'classrooms/r1/members', uid), { name: uid });
    b.update(doc(d, 'classrooms/r1'), { memberUids: arrayUnion(uid) });
    b.delete(doc(d, 'classrooms/r1/joinRequests', uid));
    return b.commit();
  }
  it('the master approves, and you are in', async () => {
    await needApproval();
    await request('eve');
    await assertSucceeds(approve('eve', 'master'));
    await assertSucceeds(getDoc(room('eve')));
  });
  it('nobody else can approve, and the master can’t add someone who never asked', async () => {
    await needApproval();
    await request('eve');
    await assertFails(approve('eve', 'co'));
    await assertFails(approve('eve', 'amy'));
    await assertFails(setDoc(doc(db('master'), 'classrooms/r1/members/mal'), { name: 'mal' }));
  });
  it('managers can see who’s waiting; other members and outsiders cannot', async () => {
    await needApproval();
    await request('eve');
    await assertSucceeds(getDocs(collection(db('master'), 'classrooms/r1/joinRequests')));
    await assertSucceeds(getDocs(collection(db('co'), 'classrooms/r1/joinRequests')));
    await assertFails(getDocs(collection(db('amy'), 'classrooms/r1/joinRequests')));
    await assertFails(getDocs(collection(db('mal'), 'classrooms/r1/joinRequests')));
  });
  it('a master can decline', async () => {
    await needApproval();
    await request('eve');
    await assertSucceeds(deleteDoc(doc(db('master'), 'classrooms/r1/joinRequests/eve')));
  });
  it('the master can flip approval on the code, and nothing else about it', async () => {
    await assertSucceeds(updateDoc(doc(db('master'), 'inviteCodes', CODE), { approval: true }));
    await assertFails(updateDoc(doc(db('amy'), 'inviteCodes', CODE), { approval: false }));
    await assertFails(updateDoc(doc(db('master'), 'inviteCodes', CODE), { classroomId: 'other' }));
  });
});

describe('leaving', () => {
  async function leave(uid) {
    const d = db(uid);
    const b = writeBatch(d);
    const members = ['master', 'co', 'amy', 'ben'].filter((m) => m !== uid);
    b.update(doc(d, 'classrooms/r1'), { memberUids: members, coMasterUids: ['co'].filter((m) => m !== uid) });
    b.delete(doc(d, 'classrooms/r1/members', uid));
    return b.commit();
  }
  it('a member or co-master can leave', async () => {
    await seed();
    await assertSucceeds(leave('amy'));
    await assertFails(getDoc(room('amy')));
    await seed();
    await assertSucceeds(leave('co'));
  });
  it('you can’t remove someone else by “leaving”', async () => {
    await seed();
    await assertFails(updateDoc(room('amy'), { memberUids: ['master', 'co', 'amy'] }));
    await assertFails(updateDoc(room('amy'), { memberUids: ['master', 'co', 'ben'], coMasterUids: ['amy'] }));
  });
  it('you can’t delete your member record while staying in the classroom', async () => {
    await seed();
    await assertFails(deleteDoc(doc(db('amy'), 'classrooms/r1/members/amy')));
  });
  const handOver = (uid, next) => {
    const d = db(uid);
    const b = writeBatch(d);
    b.update(doc(d, 'classrooms/r1'), {
      masterUid: next,
      memberUids: ['master', 'co', 'amy', 'ben'].filter((m) => m !== uid),
      coMasterUids: ['co'].filter((m) => m !== next),
    });
    b.delete(doc(d, 'classrooms/r1/members', uid));
    return b.commit();
  };
  it('a master can pass the classroom to a co-master by leaving', async () => {
    await seed();
    await assertSucceeds(handOver('master', 'co'));
    await assertFails(getDoc(room('master')));
    await assertSucceeds(updateDoc(room('co'), { title: 'Mine now' }));
  });
  it('but not to someone who isn’t a co-master, and nobody else can take it', async () => {
    await seed();
    await assertFails(handOver('master', 'amy'));
    await assertFails(handOver('co', 'co'));
    await assertFails(handOver('amy', 'amy'));
  });
});

describe('deleting a classroom', () => {
  const markDeleting = (uid) => updateDoc(room(uid), { status: 'deleting' });
  it('only the master can start or finish it', async () => {
    await seed();
    await assertFails(markDeleting('amy'));
    await assertFails(deleteDoc(room('co')));
    await assertSucceeds(markDeleting('master'));
    await assertSucceeds(deleteDoc(room('master')));
  });
  it('the master can remove their own record once deleting', async () => {
    await seed();
    await markDeleting('master');
    await assertSucceeds(deleteDoc(doc(db('master'), 'classrooms/r1/members/master')));
  });
});

describe('classroom settings', () => {
  it('only the master changes settings', async () => {
    await seed();
    await assertSucceeds(updateDoc(room('master'), { title: 'Renamed', approvalRequired: true }));
    await assertFails(updateDoc(room('co'), { title: 'Nope' }));
    await assertFails(updateDoc(room('amy'), { approvalRequired: false }));
  });
  it('only the master assigns a co-master or removes a member', async () => {
    await seed();
    await assertSucceeds(updateDoc(room('master'), { coMasterUids: ['co', 'amy'] }));
    await assertFails(updateDoc(room('amy'), { coMasterUids: ['amy'] }));
    await assertFails(deleteDoc(doc(db('amy'), 'classrooms/r1/members/ben')));
    await assertSucceeds(deleteDoc(doc(db('master'), 'classrooms/r1/members/ben')));
    await assertFails(deleteDoc(doc(db('master'), 'classrooms/r1/members/master')));
  });
  it('even the master cannot give the classroom away by accident', async () => {
    await seed();
    await assertFails(updateDoc(room('master'), { masterUid: 'amy' }));
    await assertFails(updateDoc(room('master'), { inviteCode: 'NEW234' }));
  });
});

describe('phases', () => {
  it('masters and co-masters edit phases; members do not', async () => {
    await seed();
    const p = (uid) => doc(db(uid), 'classrooms/r1/phases/p2');
    await assertSucceeds(setDoc(p('master'), { title: 'Two', order: 2 }));
    await assertSucceeds(updateDoc(p('co'), { title: 'Second' }));
    await assertFails(updateDoc(p('amy'), { title: 'Nope' }));
    await assertFails(deleteDoc(p('amy')));
  });
});

describe('steps', () => {
  const s = (uid, id) => doc(db(uid), 'classrooms/r1/steps', id);
  it('members add and change only their own', async () => {
    await seed();
    await assertSucceeds(setDoc(s('amy', 'new'), step('amy')));
    await assertFails(setDoc(s('amy', 'forben'), step('ben')));
    await assertSucceeds(updateDoc(s('amy', 'amys'), { title: 'Mine' }));
    await assertFails(updateDoc(s('amy', 'bens'), { title: 'Not mine' }));
    await assertFails(deleteDoc(s('amy', 'bens')));
    await assertSucceeds(deleteDoc(s('amy', 'amys')));
  });
  it('masters and co-masters change anyone’s', async () => {
    await seed();
    await assertSucceeds(updateDoc(s('master', 'bens'), { title: 'M' }));
    await assertSucceeds(updateDoc(s('co', 'bens'), { title: 'C' }));
    await assertSucceeds(setDoc(s('co', 'forben'), step('ben')));
  });
  it('outsiders change nothing', async () => {
    await seed();
    await assertFails(updateDoc(s('eve', 'amys'), { title: 'Eve' }));
    await assertFails(setDoc(s('eve', 'new'), step('eve')));
  });
  it('you can hand your own step to a member, but not to an outsider', async () => {
    await seed();
    await assertSucceeds(updateDoc(s('amy', 'amys'), { ownerUid: 'ben' }));
    await assertFails(updateDoc(s('ben', 'bens'), { ownerUid: 'eve' }));
  });
  it('anyone can clear a deleted step from what another step needs, nothing more', async () => {
    await seed();
    await assertFails(updateDoc(s('amy', 'bens'), { dependsOn: ['amys', 'extra'] }));
    await assertSucceeds(updateDoc(s('amy', 'bens'), { dependsOn: [] }));
  });
  describe('with approval on', () => {
    it('a member can send for approval, but not finish', async () => {
      await seed({ approval: true });
      await assertSucceeds(updateDoc(s('amy', 'amys'), { status: 'review' }));
      await assertFails(updateDoc(s('amy', 'amys'), { status: 'done' }));
      await assertFails(setDoc(s('amy', 'new'), step('amy', { status: 'done' })));
    });
    it('the master approves', async () => {
      await seed({ approval: true });
      await assertSucceeds(updateDoc(s('master', 'amys'), { status: 'done' }));
    });
  });
  it('with approval off, a member finishes their own', async () => {
    await seed();
    await assertSucceeds(updateDoc(s('amy', 'amys'), { status: 'done' }));
  });
});

describe('activity', () => {
  const a = (uid, id = 'x') => doc(db(uid), 'classrooms/r1/activity', id);
  const entry = (uid) => ({ actorUid: uid, kind: 'stepEdited', summary: 's', createdAt: serverTimestamp() });
  it('members log their own actions and read the log', async () => {
    await seed();
    await assertSucceeds(setDoc(a('amy'), entry('amy')));
    await assertSucceeds(getDocs(collection(db('ben'), 'classrooms/r1/activity')));
  });
  it('nobody can log in another’s name, or rewrite an entry', async () => {
    await seed();
    await assertFails(setDoc(a('amy'), entry('ben')));
    await assertFails(setDoc(a('eve'), entry('eve')));
    await setDoc(a('amy'), entry('amy'));
    await assertFails(updateDoc(a('amy'), { summary: 'changed' }));
    await assertFails(updateDoc(a('master'), { summary: 'changed' }));
  });
  it('only the master can delete an entry', async () => {
    await seed();
    await setDoc(a('amy'), entry('amy'));
    await assertFails(deleteDoc(a('amy')));
    await assertFails(deleteDoc(a('co')));
    await assertFails(deleteDoc(a('eve')));
    await assertSucceeds(deleteDoc(a('master')));
  });
});

describe('members and profiles', () => {
  it('you update only your own name and last visit', async () => {
    await seed();
    const m = (uid, id) => doc(db(uid), 'classrooms/r1/members', id);
    await assertSucceeds(updateDoc(m('amy', 'amy'), { name: 'Amy', lastSeenAt: serverTimestamp() }));
    await assertFails(updateDoc(m('amy', 'ben'), { name: 'Hacked' }));
    await assertFails(updateDoc(m('amy', 'amy'), { role: 'master' }));
  });
  it('profiles are yours to write', async () => {
    await assertSucceeds(setDoc(doc(db('amy'), 'users/amy'), { name: 'Amy' }));
    await assertFails(setDoc(doc(db('amy'), 'users/ben'), { name: 'Ben' }));
  });
  it('anything not named is closed', async () => {
    await assertFails(getDoc(doc(db('amy'), 'other/thing')));
    await assertFails(setDoc(doc(db('amy'), 'other/thing'), { a: 1 }));
  });
});
