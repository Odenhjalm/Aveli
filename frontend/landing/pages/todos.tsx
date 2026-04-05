import Head from 'next/head';
import type {
  GetServerSideProps,
  GetServerSidePropsContext,
  InferGetServerSidePropsType,
} from 'next';
import { createClient } from '../utils/supabase/server';

type Todo = {
  id: number | string;
  name: string;
};

type TodosPageProps = {
  todos: Todo[];
};

export const getServerSideProps: GetServerSideProps<TodosPageProps> = async (
  context: GetServerSidePropsContext
) => {
  const supabase = createClient(context);
  const { data: todos } = await supabase.from('todos').select('id, name');

  return {
    props: {
      todos: todos ?? [],
    },
  };
};

export default function TodosPage({
  todos,
}: InferGetServerSidePropsType<typeof getServerSideProps>) {
  return (
    <>
      <Head>
        <title>Aveli Todos</title>
      </Head>
      <main>
        <ul>
          {todos.map((todo) => (
            <li key={todo.id}>{todo.name}</li>
          ))}
        </ul>
      </main>
    </>
  );
}
