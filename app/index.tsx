import { Loading, Screen } from '../src/components/ui';

// The root gate in _layout redirects from here once the session is known.
export default function Index() {
  return (
    <Screen>
      <Loading />
    </Screen>
  );
}
