export type ErrorCode =
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'validation_error'
  | 'internal';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export function unauthorized(message: string): ApiError {
  return new ApiError(401, 'unauthorized', message);
}

export function forbidden(message: string): ApiError {
  return new ApiError(403, 'forbidden', message);
}

export function notFound(resource: string): ApiError {
  return new ApiError(404, 'not_found', `${resource} not found`);
}

export function validationError(message: string): ApiError {
  return new ApiError(400, 'validation_error', message);
}

export function internal(message: string): ApiError {
  return new ApiError(500, 'internal', message);
}
