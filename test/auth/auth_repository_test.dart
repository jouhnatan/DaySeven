import 'package:dayseven/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('the address a username maps to', () {
    test('uses a real top-level domain', () {
      // Supabase Auth rejects `.local` and its like on sign-up, so the domain
      // has to be one its validator accepts.
      final domain = syntheticEmailFor('aldric').split('@').last;

      expect(domain, isNot(endsWith('.local')));
      expect(domain, isNot(endsWith('.invalid')));
      expect(domain, isNot(endsWith('.test')));
      expect(domain, matches(RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$')));
    });

    test('is a well-formed address', () {
      expect(
        syntheticEmailFor('aldric'),
        matches(RegExp(r'^[a-z0-9_-]+@[a-z0-9.-]+\.[a-z]{2,}$')),
      );
    });

    test('is built from the normalised username', () {
      expect(syntheticEmailFor('  Aldric  '), syntheticEmailFor('aldric'));
    });
  });

  group('what a username may be', () {
    test('accepts the ordinary shapes', () {
      expect(usernameProblem('aldric'), isNull);
      expect(usernameProblem('house_vane-01'), isNull);
      expect(usernameProblem('  Aldric '), isNull);
    });

    test('rejects what the database would reject', () {
      expect(usernameProblem(''), isNotNull);
      expect(usernameProblem('ab'), isNotNull);
      expect(usernameProblem('a' * 33), isNotNull);
      expect(usernameProblem('has spaces'), isNotNull);
      expect(usernameProblem('no@sign'), isNotNull);
    });
  });

  group('errors that are really project settings', () {
    test('an unconfirmed email explains itself, and keeps the detail', () {
      final described = describeError(
        const AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      );

      expect(described, contains('username-only'));
      expect(described, contains('Confirm email'));
      expect(
        described,
        contains('Email not confirmed'),
        reason: 'the raw failure is still there to paste',
      );
    });

    test('the email rate limit explains itself too', () {
      final described = describeError(
        const AuthApiException(
          'email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );

      expect(described, contains('Confirm email'));
      expect(described, contains('429'));
    });

    test('an ordinary auth failure is left alone', () {
      final described = describeError(
        const AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );

      expect(described, isNot(contains('Confirm email')));
    });
  });
}
