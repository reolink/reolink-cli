import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(__dirname, '../..');
const SKILL_PATH = join(PLUGIN_ROOT, 'skills/reolink-cli/SKILL.md');

function loadSkill() {
  try {
    return readFileSync(SKILL_PATH, 'utf-8');
  } catch {
    return null;
  }
}

export const ReolinkPlugin = async () => {
  const skill = loadSkill();
  if (!skill) return {};

  return {
    'experimental.chat.messages.transform': ({ messages }) => {
      if (!messages?.length) return messages;
      const firstUser = messages.findIndex(m => m.role === 'user');
      if (firstUser === -1) return messages;
      const result = [...messages];
      result.splice(firstUser, 0, {
        role: 'system',
        content: `<skill name="reolink-cli">\n${skill}\n</skill>`,
      });
      return result;
    },
  };
};

export default ReolinkPlugin;
