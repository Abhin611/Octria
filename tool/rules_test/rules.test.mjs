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
  Bytes,
  collection,
  collectionGroup,
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
  it('you cannot give your own step away directly; it takes a handover request', async () => {
    await seed();
    await assertFails(updateDoc(s('amy', 'amys'), { ownerUid: 'ben' }));
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

describe('private comments and suggestions', () => {
  // amys belongs to amy. A thread on it is between amy and one other person.
  const thread = (author, other = author, extra = {}) => ({
    authorUid: author,
    text: 'Nice',
    participants: ['amy', other === 'amy' ? author : other],
    createdAt: serverTimestamp(),
    ...extra,
  });
  const commentDoc = (uid, id = 'c1') => doc(db(uid), 'classrooms/r1/steps/amys/comments', id);
  const sugg = (from, extra = {}) => ({
    targetType: 'step',
    targetId: 'amys',
    fromUid: from,
    toUid: 'amy',
    participants: [from, 'amy'],
    text: 'Try this',
    status: 'open',
    public: false,
    publicAt: null,
    createdAt: serverTimestamp(),
    ...extra,
  });
  const suggDoc = (uid) => doc(db(uid), 'classrooms/r1/suggestions/g1');
  const comments = (uid) =>
    query(collection(db(uid), 'classrooms/r1/steps/amys/comments'), where('participants', 'array-contains', uid));

  it('a comment is seen only by the step owner and the one person in the thread', async () => {
    await seed();
    await assertSucceeds(setDoc(commentDoc('ben'), thread('ben')));
    await assertSucceeds(getDoc(doc(db('ben'), 'classrooms/r1/steps/amys/comments/c1')));
    await assertSucceeds(getDoc(doc(db('amy'), 'classrooms/r1/steps/amys/comments/c1')));
    await assertFails(getDoc(doc(db('co'), 'classrooms/r1/steps/amys/comments/c1')));
    await assertFails(getDoc(doc(db('master'), 'classrooms/r1/steps/amys/comments/c1')));
    await assertSucceeds(getDocs(comments('ben')));
    await assertFails(getDocs(collection(db('master'), 'classrooms/r1/steps/amys/comments')));
  });

  it('a thread must include the step owner and only members, written as yourself', async () => {
    await seed();
    await assertFails(setDoc(commentDoc('ben'), thread('ben', 'ben', { participants: ['ben', 'co'] })));
    await assertFails(setDoc(commentDoc('ben'), thread('ben', 'ben', { participants: ['ben', 'stranger'] })));
    await assertFails(setDoc(commentDoc('ben'), thread('ben', 'ben', { participants: ['amy', 'co'] })));
    await assertFails(setDoc(commentDoc('ben'), thread('amy', 'ben')));
    await assertFails(setDoc(commentDoc('ben'), thread('ben', 'ben', { text: '' })));
    await assertSucceeds(setDoc(commentDoc('amy'), thread('amy', 'ben')));
  });

  it('nobody edits a comment, and only its author removes it', async () => {
    await seed();
    await setDoc(commentDoc('ben'), thread('ben'));
    await assertFails(updateDoc(commentDoc('ben'), { text: 'Changed' }));
    await assertFails(deleteDoc(commentDoc('amy')));
    await assertFails(deleteDoc(commentDoc('master')));
    await assertSucceeds(deleteDoc(commentDoc('ben')));
  });

  it('a suggestion is private unless one of the two makes it public', async () => {
    await seed();
    await assertSucceeds(setDoc(suggDoc('ben'), sugg('ben')));
    await assertFails(getDoc(suggDoc('co')));
    await assertSucceeds(getDoc(suggDoc('amy')));
    await assertFails(updateDoc(suggDoc('co'), { public: true }));
    await assertSucceeds(updateDoc(suggDoc('amy'), { public: true, publicAt: serverTimestamp() }));
    await assertSucceeds(getDoc(suggDoc('co')));
    await assertSucceeds(getDocs(query(collection(db('co'), 'classrooms/r1/suggestions'), where('public', '==', true))));
    await assertFails(getDocs(collection(db('co'), 'classrooms/r1/suggestions')));
    await assertSucceeds(updateDoc(suggDoc('ben'), { public: false, publicAt: null }));
    await assertFails(getDoc(suggDoc('co')));
  });

  it('suggestions go to the step owner, who alone answers, once', async () => {
    await seed();
    await assertFails(setDoc(suggDoc('ben'), sugg('ben', { toUid: 'co', participants: ['ben', 'co'] })));
    await assertFails(setDoc(suggDoc('ben'), sugg('amy', { participants: ['amy', 'amy'] })));
    await assertFails(setDoc(suggDoc('ben'), sugg('ben', { status: 'accepted' })));
    await assertSucceeds(setDoc(suggDoc('ben'), sugg('ben')));
    await assertFails(updateDoc(suggDoc('ben'), { status: 'accepted' }));
    await assertFails(updateDoc(suggDoc('master'), { status: 'accepted' }));
    await assertFails(updateDoc(suggDoc('amy'), { status: 'accepted', text: 'Changed' }));
    await assertSucceeds(updateDoc(suggDoc('amy'), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertFails(updateDoc(suggDoc('amy'), { status: 'dismissed', answeredAt: serverTimestamp() }));
  });
});

describe('class chat', () => {
  const msg = (uid, extra = {}) => ({
    authorUid: uid,
    text: 'Hello',
    forEveryone: false,
    appliedBy: [],
    createdAt: serverTimestamp(),
    ...extra,
  });
  const m = (uid) => doc(db(uid), 'classrooms/r1/chat/m1');

  it('members read and write it as themselves; outsiders cannot', async () => {
    await seed();
    await assertSucceeds(setDoc(m('ben'), msg('ben')));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/chat/m2'), msg('amy')));
    await assertFails(setDoc(doc(db('stranger'), 'classrooms/r1/chat/m3'), msg('stranger')));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/chat/m4'), msg('ben', { appliedBy: ['ben'] })));
    await assertSucceeds(getDocs(collection(db('amy'), 'classrooms/r1/chat')));
    await assertFails(getDocs(collection(db('stranger'), 'classrooms/r1/chat')));
  });

  it('each person only marks or unmarks themselves on a group suggestion', async () => {
    await seed();
    await setDoc(m('ben'), msg('ben', { forEveryone: true }));
    await assertSucceeds(updateDoc(m('amy'), { appliedBy: arrayUnion('amy') }));
    await assertFails(updateDoc(m('co'), { appliedBy: ['amy', 'co', 'master'] }));
    await assertFails(updateDoc(m('co'), { appliedBy: [] }));
    await assertFails(updateDoc(m('amy'), { text: 'Changed' }));
    await assertSucceeds(updateDoc(m('amy'), { appliedBy: [] }));
  });

  it('plain messages cannot be marked done; author or master removes', async () => {
    await seed();
    await setDoc(m('ben'), msg('ben'));
    await assertFails(updateDoc(m('amy'), { appliedBy: arrayUnion('amy') }));
    await assertFails(deleteDoc(m('amy')));
    await assertSucceeds(deleteDoc(m('master')));
  });
});

describe('inbox', () => {
  const note = (actor, extra = {}) => ({
    classroomId: 'r1',
    actorUid: actor,
    kind: 'commented',
    summary: 'Ben commented',
    targetId: 'amys',
    createdAt: serverTimestamp(),
    ...extra,
  });

  it('only classmates leave notes, as themselves, and only the owner reads them', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('ben'), 'users/amy/inbox/n1'), note('ben')));
    await assertFails(setDoc(doc(db('ben'), 'users/amy/inbox/n2'), note('co')));
    await assertFails(setDoc(doc(db('stranger'), 'users/amy/inbox/n3'), note('stranger')));
    await assertFails(setDoc(doc(db('ben'), 'users/stranger/inbox/n4'), note('ben')));
    await assertSucceeds(getDocs(collection(db('amy'), 'users/amy/inbox')));
    await assertFails(getDocs(collection(db('ben'), 'users/amy/inbox')));
    await assertFails(updateDoc(doc(db('amy'), 'users/amy/inbox/n1'), { summary: 'x' }));
    await assertSucceeds(deleteDoc(doc(db('amy'), 'users/amy/inbox/n1')));
  });

  it('notifications remember when you last looked, only for you', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('amy'), 'users/amy'), { notificationsSeenAt: serverTimestamp() }, { merge: true }));
    await assertFails(setDoc(doc(db('ben'), 'users/amy'), { notificationsSeenAt: serverTimestamp() }, { merge: true }));
  });
});

describe('step descriptions', () => {
  it('only the step owner writes the description, even over the master', async () => {
    await seed();
    await assertSucceeds(updateDoc(doc(db('amy'), 'classrooms/r1/steps/amys'), { description: 'My plan' }));
    await assertFails(updateDoc(doc(db('master'), 'classrooms/r1/steps/amys'), { description: 'Master says' }));
    await assertSucceeds(updateDoc(doc(db('master'), 'classrooms/r1/steps/amys'), { title: 'Renamed' }));
    await assertFails(setDoc(doc(db('master'), 'classrooms/r1/steps/new1'), step('amy', { description: 'For you' })));
    await assertSucceeds(setDoc(doc(db('master'), 'classrooms/r1/steps/new2'), step('amy')));
  });

  it('members update when they last opened the chat', async () => {
    await seed();
    await assertSucceeds(updateDoc(doc(db('amy'), 'classrooms/r1/members/amy'), { chatSeenAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db('ben'), 'classrooms/r1/members/amy'), { chatSeenAt: serverTimestamp() }));
  });
});

describe('private chats', () => {
  const thread = (people, by) => ({
    participants: people,
    createdBy: by,
    createdAt: serverTimestamp(),
    lastAt: null,
    lastText: '',
    lastBy: '',
    readAt: {},
  });

  it('two people share one chat that only they can read', async () => {
    await seed();
    const t = (uid) => doc(db(uid), 'classrooms/r1/threads/dm_amy_ben');
    await assertFails(setDoc(t('ben'), thread(['ben', 'amy'], 'ben')));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/threads/dm_amy_co'), thread(['amy', 'ben'], 'ben')));
    await assertSucceeds(setDoc(t('ben'), thread(['amy', 'ben'], 'ben')));
    await assertSucceeds(getDoc(t('amy')));
    await assertFails(getDoc(t('master')));
    const msg = (uid) => doc(db(uid), 'classrooms/r1/threads/dm_amy_ben/messages', `${uid}-m`);
    await assertSucceeds(setDoc(msg('ben'), { authorUid: 'ben', text: 'Hi', createdAt: serverTimestamp() }));
    await assertFails(setDoc(msg('co'), { authorUid: 'co', text: 'Hi', createdAt: serverTimestamp() }));
    await assertFails(setDoc(msg('amy'), { authorUid: 'ben', text: 'Hi', createdAt: serverTimestamp() }));
    await assertSucceeds(getDocs(collection(db('amy'), 'classrooms/r1/threads/dm_amy_ben/messages')));
    await assertFails(getDocs(collection(db('master'), 'classrooms/r1/threads/dm_amy_ben/messages')));
  });

  it('a group chat holds only members, and each marks only their own reading', async () => {
    await seed();
    const g = (uid) => doc(db(uid), 'classrooms/r1/threads/g1');
    await assertFails(setDoc(g('ben'), thread(['ben', 'stranger', 'amy'], 'ben')));
    await assertFails(setDoc(g('ben'), thread(['amy', 'co'], 'ben')));
    await assertSucceeds(setDoc(g('ben'), thread(['ben', 'amy', 'co'], 'ben')));
    await assertSucceeds(getDocs(query(collection(db('co'), 'classrooms/r1/threads'), where('participants', 'array-contains', 'co'))));
    await assertFails(getDocs(collection(db('master'), 'classrooms/r1/threads')));
    await assertSucceeds(updateDoc(g('amy'), { 'readAt.amy': serverTimestamp() }));
    await assertFails(updateDoc(g('amy'), { 'readAt.ben': serverTimestamp() }));
    await assertFails(updateDoc(g('amy'), { participants: ['amy', 'ben'] }));
    await assertFails(updateDoc(g('master'), { 'readAt.master': serverTimestamp() }));
  });
});

describe('handovers', () => {
  const ask = (from, to, status, extra = {}) => ({
    fromUid: from,
    toUid: to,
    participants: [from, to],
    note: '',
    status,
    createdAt: serverTimestamp(),
    ...extra,
  });
  const h = (uid) => doc(db(uid), 'classrooms/r1/handovers/amys');

  it('owners cannot simply give their step away any more', async () => {
    await seed();
    await assertFails(updateDoc(doc(db('amy'), 'classrooms/r1/steps/amys'), { ownerUid: 'ben' }));
    await assertSucceeds(updateDoc(doc(db('master'), 'classrooms/r1/steps/amys'), { ownerUid: 'ben' }));
  });

  it('a member asks the master first; then the receiver takes it on', async () => {
    await seed();
    await assertFails(setDoc(h('amy'), ask('amy', 'ben', 'needsReceiver')));
    await assertFails(setDoc(h('ben'), ask('ben', 'co', 'needsMaster')));
    await assertSucceeds(setDoc(h('amy'), ask('amy', 'ben', 'needsMaster')));
    await assertFails(getDoc(doc(db('stranger'), 'classrooms/r1/handovers/amys')));
    await assertSucceeds(getDoc(h('co')));
    // Not yet the receiver's turn.
    await assertFails(updateDoc(h('ben'), { status: 'accepted', decidedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db('ben'), 'classrooms/r1/steps/amys'), { ownerUid: 'ben' }));
    await assertFails(updateDoc(h('amy'), { status: 'needsReceiver', decidedBy: 'amy', decidedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(h('master'), { status: 'needsReceiver', decidedBy: 'master', decidedAt: serverTimestamp() }));
    // Now Ben can take it, and only for himself.
    await assertFails(updateDoc(doc(db('amy'), 'classrooms/r1/steps/amys'), { ownerUid: 'co' }));
    await assertFails(updateDoc(doc(db('ben'), 'classrooms/r1/steps/amys'), { ownerUid: 'ben', title: 'Mine now' }));
    const bens = db('ben');
    const b = writeBatch(bens);
    b.update(doc(bens, 'classrooms/r1/steps/amys'), { ownerUid: 'ben' });
    b.update(doc(bens, 'classrooms/r1/handovers/amys'), { status: 'accepted', decidedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
  });

  it('a master’s own request goes straight to the receiver', async () => {
    await seed();
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'classrooms/r1/steps/mine'), step('master')));
    const m = (uid) => doc(db(uid), 'classrooms/r1/handovers/mine');
    await assertFails(setDoc(m('master'), ask('master', 'ben', 'needsMaster')));
    await assertSucceeds(setDoc(m('master'), ask('master', 'ben', 'needsReceiver')));
    await assertSucceeds(updateDoc(m('ben'), { status: 'declined', decidedAt: serverTimestamp() }));
    await assertFails(updateDoc(m('ben'), { status: 'accepted', decidedAt: serverTimestamp() }));
  });
});

describe('owner-only study materials', () => {
  const material = (uid, extra = {}) => ({
    type: 'link',
    title: 'Docs',
    url: 'https://example.org',
    note: '',
    ownerUid: uid,
    stepId: 'amys',
    createdAt: serverTimestamp(),
    ...extra,
  });

  it('only the step owner adds and sees a step’s materials; practice links are for all', async () => {
    await seed();
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/resources/b1'), material('ben')));
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/resources/a1'), material('amy')));
    await assertFails(getDoc(doc(db('master'), 'classrooms/r1/resources/a1')));
    await assertFails(getDoc(doc(db('ben'), 'classrooms/r1/resources/a1')));
    await assertSucceeds(setDoc(doc(db('ben'), 'classrooms/r1/resources/p1'), material('ben', { type: 'practice', stepId: '' })));
    await assertSucceeds(getDoc(doc(db('co'), 'classrooms/r1/resources/p1')));
    await assertSucceeds(getDocs(query(collection(db('co'), 'classrooms/r1/resources'), where('type', '==', 'practice'))));
    await assertFails(getDocs(collection(db('co'), 'classrooms/r1/resources')));
  });
});

describe('drive files', () => {
  const file = (uid, extra = {}) => ({
    name: 'Notes.pdf',
    mimeType: 'application/pdf',
    size: 2048,
    url: 'https://drive.google.com/file/d/abc/view',
    ownerUid: uid,
    stepId: '',
    shared: true,
    createdAt: serverTimestamp(),
    ...extra,
  });

  it('members add their own Drive files and everyone reads the shared ones', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/files/f1'), file('amy')));
    await assertSucceeds(getDoc(doc(db('ben'), 'classrooms/r1/files/f1')));
    await assertSucceeds(getDocs(query(collection(db('ben'), 'classrooms/r1/files'), where('shared', '==', true))));
    await assertFails(getDoc(doc(db('outsider'), 'classrooms/r1/files/f1')));
    await assertFails(setDoc(doc(db('outsider'), 'classrooms/r1/files/f2'), file('outsider')));
    // As someone else, or pointing anywhere but Drive.
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/files/f3'), file('amy')));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/files/f4'), file('ben', { url: 'https://evil.example/x' })));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/files/f5'), file('ben', { extra: 1 })));
  });

  it('a private file is only its owner’s', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/files/p1'), file('amy', { shared: false })));
    await assertSucceeds(getDoc(doc(db('amy'), 'classrooms/r1/files/p1')));
    await assertFails(getDoc(doc(db('master'), 'classrooms/r1/files/p1')));
    await assertFails(getDocs(collection(db('ben'), 'classrooms/r1/files')));
  });

  it('only a step’s owner files under it; only the owner changes sharing', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/files/s1'), file('amy', { stepId: 'amys' })));
    await assertFails(setDoc(doc(db('ben'), 'classrooms/r1/files/s2'), file('ben', { stepId: 'amys' })));
    await assertSucceeds(updateDoc(doc(db('amy'), 'classrooms/r1/files/s1'), { shared: false }));
    await assertFails(updateDoc(doc(db('amy'), 'classrooms/r1/files/s1'), { name: 'Other.pdf' }));
    await assertFails(updateDoc(doc(db('master'), 'classrooms/r1/files/s1'), { shared: true }));
  });

  it('the owner or a master takes a file out of the library', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/files/f1'), file('amy')));
    await assertSucceeds(setDoc(doc(db('amy'), 'classrooms/r1/files/f2'), file('amy')));
    await assertFails(deleteDoc(doc(db('ben'), 'classrooms/r1/files/f1')));
    await assertSucceeds(deleteDoc(doc(db('co'), 'classrooms/r1/files/f1')));
    await assertSucceeds(deleteDoc(doc(db('amy'), 'classrooms/r1/files/f2')));
  });
});

describe('kanvas', () => {
  const board = (owner, extra = {}) => ({
    ownerUid: owner,
    title: 'Ideas',
    folder: '',
    data: '[]',
    updatedAt: serverTimestamp(),
    updatedBy: owner,
    classroomId: '',
    classroomMode: 'view',
    people: {},
    sharedWith: [],
    ...extra,
  });
  const k = (uid, owner = 'amy', id = 'k1') => doc(db(uid), `users/${owner}/kanvas/${id}`);

  it('a board picture is seen by whoever sees the board, and kept by its editors', async () => {
    await seed();
    const pic = (uid, size = 100) => ({ data: Bytes.fromUint8Array(new Uint8Array(size)), savedBy: uid });
    const pv = (uid) => doc(db(uid), 'users/amy/kanvas/k1/previews/f1');
    await setDoc(k('amy'), board('amy', { people: { ben: 'view', co: 'edit' }, sharedWith: ['ben', 'co'] }));
    await assertSucceeds(setDoc(pv('amy'), pic('amy')));
    await assertSucceeds(getDoc(pv('ben')));
    await assertFails(getDoc(pv('master')));
    await assertFails(setDoc(pv('ben'), pic('ben')));
    await assertSucceeds(setDoc(pv('co'), pic('co')));
    await assertFails(setDoc(pv('co'), pic('amy')));
    await assertFails(setDoc(pv('amy'), pic('amy', 300 * 1024)));
    await assertFails(setDoc(pv('amy'), { ...pic('amy'), extra: 1 }));
  });

  it('a board is private to its owner until shared', async () => {
    await seed();
    await assertFails(setDoc(k('ben'), board('amy')));
    await assertSucceeds(setDoc(k('amy'), board('amy')));
    await assertFails(getDoc(k('ben')));
    await assertFails(getDoc(k('master')));
    await assertFails(updateDoc(k('ben'), { data: '[1]', updatedBy: 'ben' }));
  });

  it('people it is shared with can look, and edit only what is on it if allowed', async () => {
    await seed();
    await setDoc(k('amy'), board('amy', { people: { ben: 'view', co: 'edit' }, sharedWith: ['ben', 'co'] }));
    await assertSucceeds(getDoc(k('ben')));
    await assertFails(updateDoc(k('ben'), { data: '[1]', updatedBy: 'ben' }));
    await assertSucceeds(updateDoc(k('co'), { data: '[2]', updatedBy: 'co', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(k('co'), { title: 'Mine', updatedBy: 'co' }));
    await assertFails(updateDoc(k('co'), { people: { co: 'edit', master: 'edit' }, updatedBy: 'co' }));
    await assertFails(deleteDoc(k('co')));
    await assertSucceeds(getDocs(query(collectionGroup(db('ben'), 'kanvas'), where('sharedWith', 'array-contains', 'ben'))));
  });

  it('a classroom it is shared with can look; members edit only when allowed', async () => {
    await seed();
    await setDoc(k('amy'), board('amy', { classroomId: 'r1' }));
    await assertSucceeds(getDoc(k('ben')));
    await assertFails(getDoc(k('stranger')));
    await assertFails(updateDoc(k('ben'), { data: '[1]', updatedBy: 'ben' }));
    await updateDoc(k('amy'), { classroomMode: 'edit' });
    await assertSucceeds(updateDoc(k('ben'), { data: '[1]', updatedBy: 'ben', updatedAt: serverTimestamp() }));
  });

  it('only the owner lists a board in a classroom, and only one that is theirs', async () => {
    await seed();
    await setDoc(k('amy'), board('amy'));
    const pin = (uid, id = 'k1') => doc(db(uid), `classrooms/r1/boards/${id}`);
    await assertFails(setDoc(pin('ben'), { ownerUid: 'amy', title: 'Ideas', stepId: 'amys' }));
    await assertFails(setDoc(pin('ben', 'none'), { ownerUid: 'ben', title: 'Ideas', stepId: '' }));
    await assertSucceeds(setDoc(pin('amy'), { ownerUid: 'amy', title: 'Ideas', stepId: 'amys' }));
    await assertSucceeds(getDocs(collection(db('ben'), 'classrooms/r1/boards')));
    await assertFails(getDocs(collection(db('stranger'), 'classrooms/r1/boards')));
    await assertFails(deleteDoc(pin('ben')));
    await assertSucceeds(deleteDoc(pin('master')));
  });

  it('saved copies follow the board: owner and editors save, viewers read', async () => {
    await seed();
    await setDoc(k('amy'), board('amy', { people: { ben: 'view', co: 'edit' }, sharedWith: ['ben', 'co'] }));
    const v = (uid, id) => doc(db(uid), `users/amy/kanvas/k1/versions/${id}`);
    const copy = (by) => ({ data: '[]', savedAt: serverTimestamp(), savedBy: by });
    await assertSucceeds(setDoc(v('amy', 'v1'), copy('amy')));
    await assertSucceeds(setDoc(v('co', 'v2'), copy('co')));
    await assertFails(setDoc(v('ben', 'v3'), copy('ben')));
    await assertSucceeds(getDoc(v('ben', 'v1')));
    await assertFails(getDoc(v('master', 'v1')));
    await assertFails(deleteDoc(v('co', 'v1')));
  });
});

describe('offers and open handovers', () => {
  const offer = (from, to, extra = {}) => ({
    kind: 'material',
    fromUid: from,
    toUid: to,
    participants: [from, to],
    status: 'pending',
    stepId: 'amys',
    title: 'Guide',
    boardOwner: '',
    boardId: '',
    edit: false,
    materialKind: 'link',
    url: 'https://example.org',
    note: '',
    createdAt: serverTimestamp(),
    ...extra,
  });
  const o = (uid) => doc(db(uid), 'classrooms/r1/offers/o1');

  it('only the two people see an offer, and only the receiver answers it once', async () => {
    await seed();
    await assertFails(setDoc(o('ben'), offer('amy', 'ben')));
    await assertFails(setDoc(o('ben'), offer('ben', 'stranger', { participants: ['ben', 'stranger'] })));
    await assertFails(setDoc(o('ben'), offer('ben', 'amy', { url: 'javascript:x' })));
    await assertFails(setDoc(o('ben'), offer('ben', 'amy', { kind: 'board', boardOwner: 'ben', boardId: 'none' })));
    await assertSucceeds(setDoc(o('ben'), offer('ben', 'amy')));
    await assertFails(getDoc(o('co')));
    await assertFails(getDoc(o('master')));
    await assertSucceeds(getDoc(o('amy')));
    await assertFails(updateDoc(o('ben'), { status: 'accepted' }));
    await assertSucceeds(updateDoc(o('amy'), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertFails(updateDoc(o('amy'), { status: 'declined', answeredAt: serverTimestamp() }));
  });

  it('everyone sees a handover, but its reason is never stored in it', async () => {
    await seed();
    const h = (uid) => doc(db(uid), 'classrooms/r1/handovers/amys');
    const ask = (note) => ({
      fromUid: 'amy', toUid: 'ben', participants: ['amy', 'ben'], note,
      status: 'needsMaster', createdAt: serverTimestamp(),
    });
    await assertFails(setDoc(h('amy'), ask('My reason')));
    await assertSucceeds(setDoc(h('amy'), ask('')));
    await assertSucceeds(getDoc(h('co')));
    await assertSucceeds(getDocs(collection(db('ben'), 'classrooms/r1/handovers')));
    await assertFails(getDocs(collection(db('stranger'), 'classrooms/r1/handovers')));
  });

  it('someone a board is shared with can take only themselves off it', async () => {
    await seed();
    const k = (uid) => doc(db(uid), 'users/amy/kanvas/k1');
    await setDoc(k('amy'), {
      ownerUid: 'amy', title: 'Ideas', folder: '', data: '[]', updatedAt: serverTimestamp(),
      updatedBy: 'amy', classroomId: '', classroomMode: 'view',
      people: { ben: 'view', co: 'edit' }, sharedWith: ['ben', 'co'],
    });
    await assertFails(updateDoc(k('ben'), { people: { ben: 'view' }, sharedWith: ['ben'] }));
    await assertFails(updateDoc(k('ben'), { people: { co: 'edit', ben: 'edit' }, sharedWith: ['co', 'ben'] }));
    await assertSucceeds(updateDoc(k('ben'), { people: { co: 'edit' }, sharedWith: ['co'] }));
    await assertFails(getDoc(k('ben')));
  });
});
