import { createApp } from './app';
import { FirebaseTokenVerifier } from './auth';

export default createApp((env) => new FirebaseTokenVerifier(env));
