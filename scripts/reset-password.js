#!/usr/bin/env node
'use strict';

const bcrypt = require('bcrypt');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const SALT_ROUNDS = 10;
const ENV_PATH = path.resolve(__dirname, '..', '.env');

function hashPassword(plain) {
  return bcrypt.hashSync(plain, SALT_ROUNDS);
}

function updateEnvFile(hashedPassword) {
  let envContent = '';
  try {
    envContent = fs.readFileSync(ENV_PATH, 'utf8');
  } catch (err) {
    console.error(`Error reading .env file: ${err.message}`);
    process.exit(1);
  }

  const lines = envContent.split('\n');
  let found = false;
  const updated = lines.map((line) => {
    if (line.startsWith('HERMES_CONTROL_PASSWORD=')) {
      found = true;
      return `HERMES_CONTROL_PASSWORD=${hashedPassword}`;
    }
    return line;
  });

  if (!found) {
    updated.push(`HERMES_CONTROL_PASSWORD=${hashedPassword}`);
  }

  fs.writeFileSync(ENV_PATH, updated.join('\n'), 'utf8');
}

function printConfirmation(hashedPassword) {
  console.log('');
  console.log('Password has been updated and hashed with bcrypt.');
  console.log('');
  console.log('Hashed value written to .env:');
  console.log(`  HERMES_CONTROL_PASSWORD=${hashedPassword}`);
  console.log('');
  console.log('Restart the server for changes to take effect:');
  console.log('  sudo systemctl restart hermes-control');
  console.log('');
}

async function promptPassword() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question('Enter new password: ', (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function main() {
  const arg = process.argv[2];

  let newPassword;
  if (arg) {
    newPassword = arg;
  } else {
    newPassword = await promptPassword();
  }

  if (!newPassword || newPassword.trim() === '') {
    console.error('Error: Password cannot be empty.');
    process.exit(1);
  }

  console.log('Hashing password with bcrypt (10 rounds)...');
  const hashed = hashPassword(newPassword.trim());
  updateEnvFile(hashed);
  printConfirmation(hashed);
}

main().catch((err) => {
  console.error('Unexpected error:', err.message);
  process.exit(1);
});
